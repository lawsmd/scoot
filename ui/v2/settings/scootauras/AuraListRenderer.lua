-- AuraListRenderer.lua - The Aura List page (ScootAuras section)
--
-- Two panes: individual trackers on the left (the narrower column), groups on
-- the right. Drag a tracker row onto a group box to add it; drag a member icon
-- to reorder it, onto another group to move it, or onto the tracker list to
-- remove it from its group. A search box on the page header filters both
-- panes. Hand-rolled rows registered for teardown via panel._scootAurasCleanup.
local addonName, addon = ...

addon.UI = addon.UI or {}

local ROW_H = 28
local ADD_ROW_H = 30
local PAD = 8
local COL_LABEL_H = 30
local ROW_ICON = 17
local ICON_SIZE = 26
local ICON_GAP = 2       -- between member cells in a group box
local BOX_HEADER_H = 26
local BOX_PAD = 8
local BOX_GAP = 10
local NOT_LOADED_TOP_GAP = 10   -- loaded block to the Not Loaded rule
local NOT_LOADED_HEADER_H = 37   -- gap + rule + label, before the first grayed row
local NONE_LOADED_TOP_GAP = 6    -- column label to the "None Loaded" placeholder
local NONE_LOADED_H = 26         -- the placeholder line and the gap under it
local BTN_SIZE = 16      -- group box action buttons
local BTN_GAP = 8
local ROW_BTN_SIZE = 13  -- tracker row action buttons (smaller rows)
local ROW_BTN_GAP = 6
local IND_W = 27         -- ON/OFF indicator width; the row textClear and box reserve math read it
-- A group member is a cell: the icon on the left, its two buttons stacked on the
-- icon's right edge, and a hover highlight wrapping both. The grid reserves the
-- column's room at rest, so the highlight never crosses a neighbour and the cell
-- rect is what the hover test reads.
local MEMBER_BTN_SIZE = 11        -- the two stacked buttons beside a member icon
local MEMBER_BTN_STACK_GAP = 2    -- between the two of them
local MEMBER_BTN_GAP = 2          -- icon right edge to the button column
local MEMBER_HALO_PAD = 2         -- icon or button edge to the highlight border
local MEMBER_STACK_H = MEMBER_BTN_SIZE * 2 + MEMBER_BTN_STACK_GAP
local MEMBER_CELL_W = MEMBER_HALO_PAD * 2 + ICON_SIZE + MEMBER_BTN_GAP + MEMBER_BTN_SIZE
local MEMBER_CELL_H = MEMBER_HALO_PAD * 2 + math.max(ICON_SIZE, MEMBER_STACK_H)
local ROW_TOP_PAD = 6    -- row top to the name line
local ROW_TEXT_GAP = 2   -- name line to the wrapped meta line
local ROW_BTN_Y = -7     -- button cluster inset from the row top
-- Trigger-to-panel gaps for the gear fly-out. The nub tip reaches 15px above
-- the panel top and the gear glyph is drawn at twice its button, so each gap
-- lands the tip a few pixels clear of the art: 24 for the 13px row gear
-- (6.5px of overhang), 18 for a member cell (the panel hangs off the cell,
-- clear of the buttons inside it), 26 for the 16px group gear.
local ROW_GEAR_GAP = 24
local MEMBER_GEAR_GAP = 18
local BOX_GEAR_GAP = 26
local MEMBER_GEAR_GLYPH_SCALE = 2

-- The group box's hover cluster, right to left: delete, the gear, the spec
-- filter, and the ON/OFF pill. The header reserves this much of its row for
-- it, with air on the left since the gear glyph is drawn at twice its
-- button; the name and the spec line under it both stop there, so the line
-- wraps before it reaches the pill.
local BOX_CLUSTER_W = BOX_PAD + 3 * (BTN_SIZE + BTN_GAP) + IND_W
local BOX_BTN_RESERVE = BOX_CLUSTER_W + 58

-- The page header: the how-to line hangs under the title at an explicit
-- width, and the search box and Import button sit on the divider line at
-- the header's bottom-right.
local HEADER_SIDE = 16           -- header inset, title and widgets alike
local SUBTITLE_TOP = 36          -- header top to the how-to line
local SUBTITLE_BOTTOM = 6        -- how-to line to the header bottom
local SUBTITLE_CLUSTER_GAP = 12  -- how-to line to the search box
local SEARCH_W = 180
local SEARCH_H = 22
local SEARCH_CLUSTER_GAP = 8     -- search box to the Import button
local SEARCH_DEBOUNCE = 0.15
local SEARCH_DEBOUNCE_KEY = "ScootAuraListSearch"
local RESIZE_DEBOUNCE_KEY = "ScootAuraListResize"
-- The Import fly-out under the Import button: a paste box, the Import
-- button, and a status line between them.
local IMPORT_W = 360
local IMPORT_INSET = 11          -- content inset (the flyout's padding + 1px border)
local IMPORT_BOX_H = 90
local IMPORT_BTN_H = 22
local IMPORT_ROW_GAP = 8         -- paste box to the button row
local IMPORT_GAP = 8             -- button to panel
local IMPORT_PREVIEW_DEBOUNCE = 0.15
local IMPORT_PREVIEW_KEY = "ScootAuraListImportPreview"
local SEARCH_DIM_ALPHA = 0.3     -- a group member the search did not match
-- The nav key this page renders under; Cleanup reads it to tell a re-render
-- from leaving the page.
local PAGE_KEY = "scootAurasList"

-- The spec restriction button. A funnel says "narrow this down", which is
-- what it does; the flat glyph matches the delete and gear art beside it.
local SPEC_ATLAS = "ui-questtrackerbutton-filter"

-- The left column holds single rows; the right holds group boxes and earns
-- the wider share.
local LEFT_FRACTION = 0.38
local DIVIDER_CLEAR_L = 12   -- left pane edge to divider
local DIVIDER_CLEAR_R = 14   -- divider to group boxes

local state = {
    active = false,
    panel = nil,
    scrollContent = nil,
    rows = {},
    dropGroups = {},      -- [gid] = { box, zone, icons = { {frame, index} } }
    leftPane = nil,
    leftDropZone = nil,
    triggers = {},        -- [key] = { spec, gear, reveal } for the two shared fly-outs
    hoverables = {},      -- every frame carrying an UpdateHover
    textRows = {},        -- rows whose height came from a text measurement
}

local KIND_LABELS = {
    buff = "Buff", debuff = "Debuff", missingbuff = "Missing Buff",
    classpower = "Class Power", classresource = "Class Resource",
}
local UNIT_LABELS = {
    player = "Player", group = "Group", target = "Target", focus = "Focus",
}
local SHAPE_LABELS = {
    icon = "Icon", bar = "Horizontal Bar", shape = "Shape",
    text = "Text", icontext = "Icon & Text",
}
-- A Class Power tracker's two shapes read as the editor names them, and a
-- Class Resource tracker's likewise.
local CLASS_POWER_SHAPE_LABELS = { bar = "Bar", text = "Number" }
local CLASS_RESOURCE_SHAPE_LABELS = { bar = "Bar", icons = "Group of Icons" }
local SHAPE_LABELS_BY_KIND = { classpower = CLASS_POWER_SHAPE_LABELS, classresource = CLASS_RESOURCE_SHAPE_LABELS }

-- One descriptor for every surface: the tracker row's meta line and the group
-- icon's hover tooltip. A kind with one possible unit (Class Power) drops the
-- "on" clause: the row has nothing to say about it.
local function TrackerMetaText(tracker)
    local SAU = addon.ScootAuras
    local shapeLabels = SHAPE_LABELS_BY_KIND[tracker.kind] or SHAPE_LABELS
    local text = (KIND_LABELS[tracker.kind] or "?")
    if not (SAU and SAU.SoleUnitForKind and SAU.SoleUnitForKind(tracker.kind)) then
        text = text .. " on " .. (UNIT_LABELS[tracker.unit] or "?")
    end
    text = text .. ", shown as " .. (shapeLabels[tracker.shape] or "?")
    local named = SAU and SAU.DescribeSpecs and SAU.DescribeSpecs(tracker.specs)
    if named then text = text .. ", " .. named end
    if tracker.enabled == false then
        text = text .. "  (disabled)"
    end
    return text
end

local RenderList

local function Refresh()
    if state.active and state.panel and state.scrollContent then
        RenderList(state.panel, state.scrollContent)
    end
end

--------------------------------------------------------------------------------
-- Drag and drop: the engine lives in AuraListDrag.lua; state and Refresh stay
-- here and are handed in once at load.
--------------------------------------------------------------------------------

local Drag = addon.ScootAurasUI.CreateAuraListDrag({
    state = state,
    refresh = Refresh,
    iconSize = ICON_SIZE,
})
local ClickGuard, CreateDropZone = Drag.ClickGuard, Drag.CreateDropZone
local BeginDrag, EndDrag = Drag.BeginDrag, Drag.EndDrag

-- One OnClick body for every spec-restriction trigger. kind is the trigger
-- key prefix: "t" loads a tracker, "g" a group.
local function OpenSpecFlyout(anchor, kind, id)
    if ClickGuard() then return end
    local SpecFlyout = addon.UI.ScootAuraSpecFlyout
    if not SpecFlyout then return end
    local SAU = addon.ScootAuras
    local isTracker = kind == "t"
    SpecFlyout.OpenFor(anchor, {
        title = isTracker and "Load this aura in..." or "Load this group in...",
        key = kind .. tostring(id),
        get = function()
            local rec = isTracker and SAU.GetTracker(id) or SAU.GetGroup(id)
            return rec and rec.specs
        end,
        toggle = function(specID)
            if isTracker then
                SAU.ToggleTrackerSpec(id, specID)
            else
                SAU.ToggleGroupSpec(id, specID)
            end
        end,
    })
end

-- One OnClick body for every gear trigger. kind is the trigger key prefix:
-- "t" a tracker (a list row, or a member cell with opts.inGroup), "g" a
-- group. opts.gap is the trigger-to-panel spacing for that surface.
local function OpenGearFlyout(anchor, kind, id, opts)
    if ClickGuard() then return end
    local GearFlyout = addon.UI.ScootAuraGearFlyout
    if not GearFlyout then return end
    opts = opts or {}
    opts.key = kind .. tostring(id)
    GearFlyout.OpenFor(anchor, kind, id, opts)
end

--------------------------------------------------------------------------------
-- Cleanup (invoked from UIPanel:ClearContent through the registered slot)
--------------------------------------------------------------------------------

local function Cleanup(panel)
    if Drag.active then EndDrag(true) end
    -- The spec and gear fly-outs outlive the page (one instance each,
    -- re-anchored per row), so close them before their anchors are destroyed.
    -- The exception is a re-render one of them asked for: RenderList hands it
    -- the rebuilt trigger instead.
    local SpecFlyout = addon.UI.ScootAuraSpecFlyout
    if SpecFlyout and not SpecFlyout.IsReanchoring() then SpecFlyout.Close() end
    local GearFlyout = addon.UI.ScootAuraGearFlyout
    if GearFlyout and not GearFlyout.IsReanchoring() then GearFlyout.Close() end
    for _, row in ipairs(state.rows) do
        row:Hide()
        row:SetParent(nil)
    end
    state.rows = {}
    state.textRows = {}
    state.hoverables = {}
    state.triggers = {}
    for gid in pairs(state.dropGroups) do
        state.dropGroups[gid] = nil
    end
    state.leftPane = nil
    state.leftDropZone = nil
    state.active = false
    panel._scootAurasCleanup = nil

    -- Header pieces this page borrows: the search box, the Import button
    -- with its fly-out, and the restyled subtitle. The widgets are built once
    -- per window and cached (not in the per-render state, which is destroyed
    -- here), and they come down only when the page is left. RenderList runs
    -- this same teardown on every rebuild, and hiding the search box then
    -- would drop the focus of a box the user is typing in. OnNavigationSelect
    -- writes the new page key before ClearContent, so the key tells the two
    -- apart.
    if panel._currentCategoryKey == PAGE_KEY then return end
    local Controls = addon.UI.Controls
    if Controls and Controls.CancelDebounce then
        Controls.CancelDebounce(SEARCH_DEBOUNCE_KEY)
        Controls.CancelDebounce(RESIZE_DEBOUNCE_KEY)
        Controls.CancelDebounce(IMPORT_PREVIEW_KEY)
    end
    local contentPane = panel.frame and panel.frame._contentPane
    if contentPane then
        contentPane._onResize = nil
        if contentPane._scootAuraImportBtn then
            contentPane._scootAuraImportBtn:Hide()
        end
        -- The pasted text stays: a user who left mid-paste gets it back.
        if contentPane._scootAuraImportFlyout then
            contentPane._scootAuraImportFlyout:Close()
        end
        local search = contentPane._scootAuraSearch
        if search then
            search:ClearFocus()
            search:SetText("")
            search:Hide()
        end
    end
    if panel.ResetHeaderSubtitle then panel:ResetHeaderSubtitle() end
end

--------------------------------------------------------------------------------
-- Header widgets: the search box and the Import button with its fly-out
--------------------------------------------------------------------------------

-- The Import fly-out hangs under the header button: a paste box, an Import
-- button, and a status line that previews what the pasted string holds and
-- names the error when the import fails. Built once per window with the
-- button, outside the per-render state: Cleanup runs on every RenderList, and
-- a failed import must keep its pasted text through a resize- or
-- search-triggered rebuild. The anchor is itself once-per-window, so no
-- reanchor bracket. Returns the flyout.
local function EnsureImportFlyout(contentPane, importBtn)
    if contentPane._scootAuraImportFlyout then return contentPane._scootAuraImportFlyout end
    local Controls = addon.UI.Controls
    if not Controls.CreateFlyout or not Controls.CreateMultiLineEditBox then return nil end
    local theme = addon.UI.Theme

    -- The button sits at the header's right edge, so the panel hangs
    -- right-aligned under it with the nub on the button.
    local flyout = Controls:CreateFlyout({
        anchor = importBtn,
        direction = "DOWN",
        align = "RIGHT",
        width = IMPORT_W,
        height = IMPORT_BOX_H + IMPORT_ROW_GAP + IMPORT_BTN_H + 2 * IMPORT_INSET,
        padding = IMPORT_INSET - 1,
        gap = IMPORT_GAP,
        name = "ScootAuraImportFlyout",
    })
    if not flyout then return nil end
    local content = flyout:GetContent()

    local pasteBox = Controls:CreateMultiLineEditBox({
        parent = content,
        width = IMPORT_W - 2 * IMPORT_INSET,
        height = IMPORT_BOX_H,
        placeholder = "Paste a Scoot aura string...",
        fontSize = 11,
    })
    pasteBox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    -- The first Escape leaves the box; the next one closes the panel.
    pasteBox._editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local status = content:CreateFontString(nil, "OVERLAY")
    status:SetFont(theme:GetFont("LABEL"), 10, "")
    status:SetJustifyH("LEFT")
    status:SetJustifyV("MIDDLE")
    status:SetWordWrap(true)
    status:SetMaxLines(2)

    local function SetStatus(text, isError)
        if isError then
            status:SetTextColor(1, 0.35, 0.35, 1)
        else
            local dr, dg, db = theme:GetDimTextColor()
            status:SetTextColor(dr, dg, db, 1)
        end
        status:SetText(text or "")
    end

    local function Trimmed()
        local text = pasteBox:GetText()
        if type(text) ~= "string" then return "" end
        return text:match("^%s*(.-)%s*$") or ""
    end

    local function DoImport()
        local SAU = addon.ScootAuras
        if InCombatLockdown() then
            SetStatus("Cannot import in combat", true)
            return
        end
        local str = Trimmed()
        if str == "" then
            SetStatus("Paste a string first", true)
            return
        end
        local result, err = SAU.ImportString(str)
        if not result then
            SetStatus(err or "Import failed", true)
            return
        end
        pasteBox:SetText("")
        SetStatus("")
        flyout:Close()
        Refresh()
    end

    local runBtn = Controls:CreateButton({
        parent = content,
        text = "Import",
        height = IMPORT_BTN_H,
        fontSize = 11,
        borderWidth = 1,
        borderAlpha = 0.6,
        onClick = DoImport,
    })
    runBtn:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    status:SetPoint("TOPLEFT", pasteBox, "BOTTOMLEFT", 0, -IMPORT_ROW_GAP)
    status:SetPoint("BOTTOMRIGHT", runBtn, "BOTTOMLEFT", -8, 0)

    -- What the pasted string holds, before anything is created. userInput
    -- alone, because the control re-asserts its text on show.
    pasteBox._editBox:HookScript("OnTextChanged", function(_, userInput)
        if not userInput then return end
        Controls.Debounce(IMPORT_PREVIEW_KEY, IMPORT_PREVIEW_DEBOUNCE, function()
            local SAU = addon.ScootAuras
            local str = Trimmed()
            if str == "" then
                SetStatus("")
                return
            end
            if not (SAU and SAU.DescribeImportString) then return end
            local info, err = SAU.DescribeImportString(str)
            if not info then
                SetStatus(err or "Import failed", true)
                return
            end
            local what
            if info.kind == "group" then
                local n = info.memberCount or 0
                what = ("Group '%s', %d %s"):format(tostring(info.name), n, n == 1 and "aura" or "auras")
            else
                what = ("Aura '%s'"):format(tostring(info.name))
            end
            if info.className then what = what .. ", " .. info.className end
            SetStatus(what, false)
        end)
    end)

    flyout._pasteBox = pasteBox
    contentPane._scootAuraImportFlyout = flyout
    return flyout
end

-- Built once per settings window on the shared page header, on the divider
-- line at the header's bottom-right in the header's small-button recipe (see
-- the Collapse All button in settingspanel/core.lua), the search box left of
-- the button. Shown by RenderList, hidden by Cleanup when the page is left.
local function EnsureHeaderWidgets(contentPane)
    if not contentPane or not contentPane._header then return end
    if contentPane._scootAuraImportBtn then return end
    local Controls = addon.UI.Controls
    if not Controls or not Controls.CreateButton or not Controls.CreateSingleLineEditBox then return end
    local header = contentPane._header

    local importBtn = Controls:CreateButton({
        parent = header,
        name = "ScootAuraImportBtn",
        text = "Import",
        height = 17,
        fontSize = 10,
        borderWidth = 1,
        borderAlpha = 0.6,
        onClick = function()
            if ClickGuard() then return end
            local flyout = contentPane._scootAuraImportFlyout
            if flyout then flyout:Toggle() end
        end,
    })
    importBtn:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -HEADER_SIDE, 8)
    importBtn:Hide()
    contentPane._scootAuraImportBtn = importBtn
    EnsureImportFlyout(contentPane, importBtn)

    -- The search box filters both panes as the user types. RenderList reads
    -- the query straight from it, so the text is the one source of truth and
    -- survives every rebuild by construction.
    local search = Controls:CreateSingleLineEditBox({
        parent = header,
        width = SEARCH_W,
        height = SEARCH_H,
        fontSize = 11,
        placeholder = "Search...",
    })
    search:SetPoint("RIGHT", importBtn, "LEFT", -SEARCH_CLUSTER_GAP, 0)
    search:Hide()
    local editBox = search._editBox
    -- HookScript: the control's own OnTextChanged drives its placeholder.
    -- userInput alone, because the control re-asserts its text on show.
    editBox:HookScript("OnTextChanged", function(_, userInput)
        if not userInput then return end
        Controls.Debounce(SEARCH_DEBOUNCE_KEY, SEARCH_DEBOUNCE, Refresh)
    end)
    -- The stock handler reverts to the text the box had when it took focus;
    -- a search box clears instead. The focused box takes this Escape, so the
    -- next one closes the window.
    editBox:SetScript("OnEscapePressed", function()
        Controls.CancelDebounce(SEARCH_DEBOUNCE_KEY)
        local had = search:GetText() ~= ""
        search:SetText("")
        search:ClearFocus()
        if had then Refresh() end
    end)
    contentPane._scootAuraSearch = search
end

-- The search box's text, trimmed and lowercased, or "" with no box or none.
local function SearchQuery(contentPane)
    local search = contentPane and contentPane._scootAuraSearch
    local text = search and search:GetText()
    if type(text) ~= "string" then return "" end
    return (text:match("^%s*(.-)%s*$") or ""):lower()
end

-- Lowercased for a plain find, or "" for anything that is not a plain
-- string: a secret name cannot be lowercased.
local function Norm(s)
    if type(s) ~= "string" or issecretvalue(s) then return "" end
    return s:lower()
end

-- A tracker matches on the name its row shows, and for a spell kind on the
-- aura's live name and its ID digits. A kind with no spell is named after
-- its resource, so its display name is the whole of it (DescribeSpell(nil)
-- would answer "Aura nil" and match every such tracker on "aura").
local function TrackerMatches(SAU, tracker, query)
    if Norm(SAU.DisplayName(tracker)):find(query, 1, true) then return true end
    if tracker.spellId and SAU.KindNeedsSpell(tracker.kind) then
        if Norm((SAU.DescribeSpell(tracker.spellId))):find(query, 1, true) then return true end
        if tostring(tracker.spellId):find(query, 1, true) then return true end
    end
    return false
end

-- A group stays on the page when its own name matches or any member does.
-- keep names the members that matched, so the box can dim the rest; it is
-- nil when the name matched, and nothing inside dims.
local function GroupMatch(SAU, gid, group, query)
    if Norm(group.name or ("Aura Group " .. gid)):find(query, 1, true) then
        return { shown = true }
    end
    local keep, any = {}, false
    for _, memberId in ipairs(group.memberOrder or {}) do
        local tracker = SAU.GetTracker(memberId)
        if tracker and TrackerMatches(SAU, tracker, query) then
            keep[memberId] = true
            any = true
        end
    end
    return { shown = any, keep = keep }
end

-- The how-to line's width: from the header's left inset to a gap short of
-- the search box. Before the header has a rect it reads 0, and a stand-in
-- keeps the header at its base height until the deferred pass in RenderList
-- lays the line out again.
local function SubtitleWidth(contentPane)
    local headerW = contentPane._header:GetWidth() or 0
    if headerW <= 0 then return 600 end
    local importBtn = contentPane._scootAuraImportBtn
    local clusterW = SEARCH_W + SEARCH_CLUSTER_GAP + ((importBtn and importBtn:GetWidth()) or 0)
    return math.max(120, headerW - HEADER_SIDE * 2 - clusterW - SUBTITLE_CLUSTER_GAP)
end

-- The header height the wrapped how-to line wants, never under the stock
-- height. GetStringHeight reports the wrapped height once the FontString
-- has an explicit width; a cold font measures short, so the deferred pass
-- in RenderList asks again.
local function HeaderHeightFor(contentPane)
    local base = contentPane._headerBaseHeight or 66
    local sub = contentPane._headerSubtitle
    local subH = (sub and sub:GetStringHeight()) or 0
    if subH <= 0 then return base end
    return math.max(base, SUBTITLE_TOP + math.ceil(subH) + SUBTITLE_BOTTOM)
end

--------------------------------------------------------------------------------
-- Shared row pieces
--------------------------------------------------------------------------------

-- The spec and gear fly-outs outlive a re-render; their triggers do not.
-- Every surface carrying them files both under the record's own key ("t<id>"
-- for a tracker, "g<gid>" for a group), so an open panel finds its
-- replacement once the rebuilt rows exist. A tracker is a list row or a group
-- member, never both, so one key covers both surfaces; reveal is the
-- surface's hover repaint, the same for both panels.
local function RegisterTriggers(key, specBtn, gearBtn, reveal)
    state.triggers[key] = { spec = specBtn, gear = gearBtn, reveal = reveal }
end

--------------------------------------------------------------------------------
-- Left pane: tracker rows
--------------------------------------------------------------------------------

-- Row height from its two text lines. GetStringHeight reports the wrapped
-- height once the FontString has an explicit width, but it can under-report
-- before a font has rendered once, so RenderList checks these again a frame
-- later and restacks if anything moved.
local function MeasuredRowHeight(name, meta)
    local nameH = name:GetStringHeight() or 0
    local metaH = meta:GetStringHeight() or 0
    if nameH <= 0 then nameH = 10 end
    if metaH <= 0 then metaH = 9 end
    return math.max(ROW_H,
        math.ceil(ROW_TOP_PAD + nameH + ROW_TEXT_GAP + metaH + ROW_TOP_PAD))
end

-- paneW arrives from the caller because a pane's rect resolves at the end of
-- the frame, too late for the meta line's wrap width (the group boxes take
-- their width the same way).
local function CreateTrackerRow(pane, trackerId, tracker, paneW, loaded)
    local theme = addon.UI.Theme
    local ar, ag, ab = theme:GetAccentColor()
    local SAU = addon.ScootAuras

    local row = CreateFrame("Frame", nil, pane)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)

    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.08)
    hoverBg:Hide()

    -- Icon and buttons hang from the top, not the middle: the row grows
    -- downward as the meta line wraps, and both belong on the name's line.
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ROW_ICON, ROW_ICON)
    icon:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -5)
    -- The spell's icon, or the class crest for a kind with no spell.
    local texture = SAU.TrackerIcon(tracker)
    SAU.PaintTrackerIcon(icon, texture)

    -- Text stops short of the button cluster, so a long name or meta line
    -- never runs under it. Four buttons: delete, gear, spec, ON.
    local textClear = PAD + IND_W + 3 * (ROW_BTN_SIZE + ROW_BTN_GAP) + 6

    local textLeft = PAD + ROW_ICON + 6
    local textW = math.max(40, (paneW or 240) - textLeft - textClear)

    local name = row:CreateFontString(nil, "OVERLAY")
    name:SetFont(theme:GetFont("LABEL"), 8, "")
    name:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -ROW_TOP_PAD)
    name:SetWidth(textW)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetText(SAU.DisplayName(tracker))
    name:SetTextColor(0.92, 0.92, 0.92, 1)

    -- Wrapped, not truncated: the list scrolls, so lines are cheaper than a
    -- descriptor that ends in an ellipsis. An explicit SetWidth is what makes
    -- GetStringHeight report the wrapped height in this same tick.
    local meta = row:CreateFontString(nil, "OVERLAY")
    meta:SetFont(theme:GetFont("LABEL"), 7, "")
    meta:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -ROW_TEXT_GAP)
    meta:SetWidth(textW)
    meta:SetJustifyH("LEFT")
    meta:SetJustifyV("TOP")
    meta:SetWordWrap(true)
    meta:SetText(TrackerMetaText(tracker))
    meta:SetTextColor(0.55, 0.55, 0.55, 1)

    row._name, row._meta = name, meta
    row:SetHeight(MeasuredRowHeight(name, meta))

    -- An unloaded aura is grayed in place: the wrong spec, or switched off. It
    -- stays fully interactive, because editing one is how it gets loaded.
    if loaded == false then
        icon:SetDesaturated(true)
        icon:SetAlpha(0.45)
        name:SetTextColor(0.5, 0.5, 0.5, 1)
        meta:SetTextColor(0.42, 0.42, 0.42, 1)
    elseif tracker.enabled == false then
        icon:SetDesaturated(true)
        name:SetTextColor(0.55, 0.55, 0.55, 1)
    end

    -- All four buttons ride the row hover. Right to left: delete, the gear
    -- (Duplicate and Export in its fly-out), spec filter, ON/OFF pill, the
    -- group box's cluster at the row's smaller size.
    local Controls = addon.UI.Controls
    local deleteBtn = Controls:CreateGlyphButton({ parent = row, atlas = "common-icon-delete",
        tooltip = "Delete", size = ROW_BTN_SIZE })
    deleteBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -PAD, ROW_BTN_Y)
    local gearBtn = Controls:CreateGlyphButton({ parent = row, atlas = "GM-icon-settings",
        tooltip = "Options", size = ROW_BTN_SIZE, glyphScale = 2 })
    gearBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -ROW_BTN_GAP, 0)
    local specBtn = Controls:CreateGlyphButton({ parent = row, atlas = SPEC_ATLAS,
        tooltip = "Loaded on these specs", size = ROW_BTN_SIZE })
    specBtn:SetPoint("RIGHT", gearBtn, "LEFT", -ROW_BTN_GAP, 0)

    local enabledBtn = Controls:CreateOnOffIndicator({ parent = row,
        width = IND_W, height = ROW_BTN_SIZE })
    enabledBtn:SetPoint("RIGHT", specBtn, "LEFT", -ROW_BTN_GAP, 0)
    enabledBtn:SetOn(tracker.enabled ~= false)
    enabledBtn:SetScript("OnEnter", function()
        if row.UpdateHover then row.UpdateHover() end
    end)
    enabledBtn:SetScript("OnLeave", function()
        if row.UpdateHover then row.UpdateHover() end
    end)

    -- IsMouseOver covers children, so moving onto a button keeps the row lit.
    -- A live drag turns the hover art off: the pointer under the ghost passes
    -- over rows that are not drop targets, and a lit row says they are. The
    -- pane's own green wash is the answer for that drag.
    row.UpdateHover = function()
        local SpecFlyout = addon.UI.ScootAuraSpecFlyout
        local GearFlyout = addon.UI.ScootAuraGearFlyout
        local over = not Drag.active
            and (row:IsMouseOver()
                or (SpecFlyout and SpecFlyout.IsOpenFor(specBtn))
                or (GearFlyout and GearFlyout.IsOpenFor(gearBtn))
                or false)
        hoverBg:SetShown(over)
        specBtn:SetShown(over)
        deleteBtn:SetShown(over)
        gearBtn:SetShown(over)
        enabledBtn:SetShown(over)
    end
    row:SetScript("OnEnter", row.UpdateHover)
    row:SetScript("OnLeave", row.UpdateHover)
    table.insert(state.hoverables, row)
    RegisterTriggers("t" .. tostring(trackerId), specBtn, gearBtn, row.UpdateHover)

    row:SetScript("OnMouseUp", function(_, button)
        if ClickGuard() then return end
        if button == "LeftButton" and addon.ShowScootAuraEditor then
            addon.ShowScootAuraEditor(trackerId)
        end
    end)

    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function()
        BeginDrag(trackerId, nil, nil, texture, row)
    end)

    enabledBtn:SetScript("OnClick", function()
        SAU.SetTrackerEnabled(trackerId, tracker.enabled == false)
        Refresh()
    end)

    specBtn:SetScript("OnClick", function()
        OpenSpecFlyout(specBtn, "t", trackerId)
    end)

    gearBtn:SetScript("OnClick", function()
        OpenGearFlyout(gearBtn, "t", trackerId, { gap = ROW_GEAR_GAP })
    end)

    deleteBtn:SetScript("OnClick", function()
        local trackerName = SAU.DisplayName(tracker)
        local doDelete = function()
            if addon.UI.ScootAuraEditor and addon.UI.ScootAuraEditor.IsOpen() then
                addon.UI.ScootAuraEditor.Close()
            end
            SAU.DeleteTracker(trackerId)
            Refresh()
        end
        if Controls and Controls.ConfirmDialog then
            Controls:ConfirmDialog(
                "Delete '" .. trackerName .. "'? Its styling and saved position are removed too.",
                doDelete)
        else
            doDelete()
        end
    end)

    return row
end

-- Add button pinned by the caller to the bottom of its pane, text centered.
local function CreateAddRow(pane, label, onClick)
    local theme = addon.UI.Theme
    local ar, ag, ab = theme:GetAccentColor()

    local row = CreateFrame("Frame", nil, pane)
    row:SetHeight(ADD_ROW_H)
    row:EnableMouse(true)

    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.1)
    hoverBg:Hide()

    local text = row:CreateFontString(nil, "OVERLAY")
    text:SetFont(theme:GetFont("LABEL"), 13, "")
    text:SetPoint("CENTER", row, "CENTER", 0, 0)
    text:SetText(label)
    text:SetTextColor(ar, ag, ab, 1)

    row:SetScript("OnEnter", function() hoverBg:Show() end)
    row:SetScript("OnLeave", function() hoverBg:Hide() end)
    row:SetScript("OnMouseUp", function(_, button)
        if ClickGuard() then return end
        if button == "LeftButton" then onClick() end
    end)

    return row
end

--------------------------------------------------------------------------------
-- Right pane: group boxes
--------------------------------------------------------------------------------

-- The spec line's wrapped height, floored at one line; the box height math
-- and the deferred re-measure both read it.
local function MeasuredSpecHeight(specFS)
    return math.ceil(math.max(9, specFS:GetStringHeight() or 9))
end

-- A restricted group says so under its name. Groups have no meta line, so
-- the header grows by this one when it is there. The line stops where the
-- name stops, clear of the hover cluster; at the box's full width it ran
-- under the buttons. Files the FontString and its measured height on the
-- box, so RenderList can re-measure once the font is warm. Returns the
-- header height.
local function AddGroupSpecLine(box, group, boxW, theme)
    local SAU = addon.ScootAuras
    local groupSpecs = SAU.DescribeSpecs and SAU.DescribeSpecs(group.specs)
    if not groupSpecs then return BOX_HEADER_H end
    local specFS = box:CreateFontString(nil, "OVERLAY")
    specFS:SetFont(theme:GetFont("LABEL"), 7, "")
    specFS:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD, -(BOX_HEADER_H - 6))
    specFS:SetWidth(math.max(40, boxW - BOX_BTN_RESERVE))
    specFS:SetJustifyH("LEFT")
    specFS:SetWordWrap(true)
    specFS:SetText(groupSpecs)
    specFS:SetTextColor(0.55, 0.55, 0.55, 1)
    box._specFS = specFS
    box._specH = MeasuredSpecHeight(specFS)
    return BOX_HEADER_H + box._specH + 2
end

-- keepSet, under a search, names the members that matched; every other
-- member's cell dims. nil means nothing dims.
local function CreateGroupBox(pane, gid, group, boxW, loaded, keepSet)
    local theme = addon.UI.Theme
    local ar, ag, ab = theme:GetAccentColor()
    local SAU = addon.ScootAuras

    local box = CreateFrame("Frame", nil, pane)
    box:EnableMouse(true)

    local bg = box:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(ar, ag, ab, 0.04)

    local zone = CreateDropZone(box)

    -- Static accent snapshot, matching the bg wash above; neither repaints on
    -- an accent change until the next re-render.
    box._border = addon.UI.Controls.CreateBorder(box, {
        color = { ar, ag, ab, 0.3 },
    })

    -- Group name plus rename pencil; the name feeds the Edit Mode container.
    local nameBtn = CreateFrame("Button", nil, box)
    nameBtn:SetHeight(18)
    nameBtn:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD, -4)
    local nameFS = nameBtn:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(theme:GetFont("LABEL"), 12, "")
    nameFS:SetPoint("LEFT", 0, 0)
    nameFS:SetText(group.name or ("Aura Group " .. gid))
    nameFS:SetTextColor(0.92, 0.92, 0.92, 1)
    nameBtn:SetWidth(math.max(20, math.min(nameFS:GetStringWidth() + 6, boxW - BOX_BTN_RESERVE)))

    local pencilBtn = CreateFrame("Button", nil, box)
    pencilBtn:SetSize(12, 12)
    pencilBtn:SetPoint("LEFT", nameBtn, "RIGHT", 4, 0)
    local pencil = pencilBtn:CreateTexture(nil, "ARTWORK")
    pencil:SetAllPoints()
    pencil:SetAtlas("Pencil-Icon")
    pencil:SetDesaturated(true)
    pencil:SetVertexColor(ar, ag, ab)
    pencil:SetAlpha(0.4)
    pencilBtn:SetScript("OnEnter", function() pencil:SetAlpha(0.9) end)
    pencilBtn:SetScript("OnLeave", function() pencil:SetAlpha(0.4) end)

    local renameBox = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    renameBox:SetHeight(18)
    renameBox:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD + 6, -4)
    -- Stops short of the cluster, which stays revealed while the pointer is
    -- in the box.
    renameBox:SetPoint("TOPRIGHT", box, "TOPRIGHT", -(BOX_CLUSTER_W + 18), -4)
    renameBox:SetAutoFocus(false)
    renameBox:SetFontObject("GameFontHighlightSmall")
    renameBox:Hide()
    local function CommitRename()
        local text = renameBox:GetText()
        renameBox:Hide()
        nameBtn:Show()
        pencilBtn:Show()
        if text and text ~= "" and text ~= group.name then
            SAU.RenameGroup(gid, text)
            Refresh()
        end
    end
    local function CancelRename()
        renameBox:Hide()
        nameBtn:Show()
        pencilBtn:Show()
    end
    renameBox:SetScript("OnEnterPressed", CommitRename)
    renameBox:SetScript("OnEscapePressed", CancelRename)
    renameBox:SetScript("OnEditFocusLost", function()
        if renameBox:IsShown() then CancelRename() end
    end)
    local function StartRename()
        if ClickGuard() then return end
        renameBox:SetText(group.name or "")
        nameBtn:Hide()
        pencilBtn:Hide()
        renameBox:Show()
        renameBox:SetFocus()
        renameBox:HighlightText()
    end
    nameBtn:SetScript("OnClick", StartRename)
    pencilBtn:SetScript("OnClick", StartRename)

    -- Hover-revealed, right to left: delete, the gear, spec filter, and the
    -- ON/OFF pill, the tracker row's cluster at the box's button size. The
    -- gear opens the group's fly-out (Duplicate, Export, and the layout
    -- controls). An unloaded group keeps the pill, since it is how a
    -- switched-off group comes back, and the gear with it; the layout
    -- controls, which describe a group on screen, hide themselves inside the
    -- panel.
    local Controls = addon.UI.Controls
    local deleteBtn = Controls:CreateGlyphButton({ parent = box, atlas = "common-icon-delete",
        tooltip = "Delete Group", size = BTN_SIZE })
    deleteBtn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -BOX_PAD, -5)
    local layoutBtn = Controls:CreateGlyphButton({ parent = box, atlas = "GM-icon-settings",
        tooltip = "Group Options", size = BTN_SIZE, glyphScale = 2 })
    layoutBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -BTN_GAP, 0)
    layoutBtn:SetScript("OnClick", function()
        OpenGearFlyout(layoutBtn, "g", gid, { gap = BOX_GEAR_GAP })
    end)

    local specBtn = Controls:CreateGlyphButton({ parent = box, atlas = SPEC_ATLAS,
        tooltip = "Loaded on these specs", size = BTN_SIZE })
    specBtn:SetPoint("RIGHT", layoutBtn, "LEFT", -BTN_GAP, 0)
    specBtn:SetScript("OnClick", function()
        OpenSpecFlyout(specBtn, "g", gid)
    end)

    local enabledBtn = Controls:CreateOnOffIndicator({ parent = box,
        width = IND_W, height = BTN_SIZE })
    enabledBtn:SetPoint("RIGHT", specBtn, "LEFT", -BTN_GAP, 0)
    enabledBtn:SetOn(group.enabled ~= false)
    enabledBtn:SetScript("OnEnter", function()
        if box.UpdateHover then box.UpdateHover() end
    end)
    enabledBtn:SetScript("OnLeave", function()
        if box.UpdateHover then box.UpdateHover() end
    end)
    enabledBtn:SetScript("OnClick", function()
        -- The box moves between the Loaded and Not Loaded blocks.
        SAU.SetGroupEnabled(gid, group.enabled == false)
        Refresh()
    end)

    deleteBtn:SetScript("OnClick", function()
        local groupName = group.name or ("Aura Group " .. gid)
        local doDelete = function()
            -- The members go too, and the editor may be open on one of them.
            if addon.UI.ScootAuraEditor and addon.UI.ScootAuraEditor.IsOpen() then
                addon.UI.ScootAuraEditor.Close()
            end
            SAU.DeleteGroup(gid)
            Refresh()
        end
        if Controls and Controls.ConfirmDialog then
            Controls:ConfirmDialog(
                "Delete '" .. groupName .. "' and every aura in it?",
                doDelete)
        else
            doDelete()
        end
    end)

    local headerH = AddGroupSpecLine(box, group, boxW, theme)

    -- Member icon grid, in memberOrder order.
    local icons = {}
    local perRow = math.max(1, math.floor((boxW - BOX_PAD * 2 + ICON_GAP) / (MEMBER_CELL_W + ICON_GAP)))
    local shown = 0
    for index, memberId in ipairs(group.memberOrder or {}) do
        local tracker = SAU.GetTracker(memberId)
        if tracker then
            local slot = shown
            shown = shown + 1
            local col = slot % perRow
            local rowIdx = math.floor(slot / perRow)
            -- The cell owns the hover art and the hover test for the icon and
            -- both buttons. Mouse is on so the pointer entering the gutter
            -- beside the icon lights it too.
            local cell = CreateFrame("Frame", nil, box)
            cell:SetSize(MEMBER_CELL_W, MEMBER_CELL_H)
            cell:SetPoint("TOPLEFT", box, "TOPLEFT",
                BOX_PAD + col * (MEMBER_CELL_W + ICON_GAP),
                -(headerH + rowIdx * (MEMBER_CELL_H + ICON_GAP)))
            cell:EnableMouse(true)
            -- A member the search did not match dims as a whole: the icon,
            -- its two buttons, and the hover art multiply with the cell.
            local dimmed = keepSet ~= nil and not keepSet[memberId]
            if dimmed then cell:SetAlpha(SEARCH_DIM_ALPHA) end

            -- The tracker row's hover language on a cell instead of a row: an
            -- accent wash under everything and a 1px accent border, both a
            -- static snapshot like the group box border above.
            local haloBg = cell:CreateTexture(nil, "BACKGROUND", nil, -8)
            haloBg:SetAllPoints()
            haloBg:SetColorTexture(ar, ag, ab, 0.08)
            haloBg:Hide()
            local haloBorder = Controls.CreateBorder(cell, {
                color = { ar, ag, ab, 0.6 },
            })
            haloBorder:SetShown(false)

            local btn = CreateFrame("Button", nil, cell)
            btn:SetSize(ICON_SIZE, ICON_SIZE)
            btn:SetPoint("LEFT", cell, "LEFT", MEMBER_HALO_PAD, 0)

            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            local texture = SAU.TrackerIcon(tracker)
            SAU.PaintTrackerIcon(tex, texture)
            if loaded == false or not SAU.IsTrackerActive(memberId, tracker) then
                tex:SetDesaturated(true)
                -- A search-dimmed cell carries the whole reduction; the
                -- icon's own alpha would multiply into it.
                if not dimmed then tex:SetAlpha(0.45) end
            end

            -- A group is shared by the whole account, but its members are often
            -- one class each, so a member's spec list and its gear (an in-group
            -- copy, an export) are reachable without pulling it out of the
            -- group first. The two stack in a column on the icon's right edge,
            -- clear of the spell art and inside the room the cell reserves for
            -- them. An unloaded member keeps both, the way a grayed tracker row
            -- does, because the spec button is how an aura gets loaded.
            local memberSpecBtn = Controls:CreateGlyphButton({ parent = cell, atlas = SPEC_ATLAS,
                tooltip = "Loaded on these specs", size = MEMBER_BTN_SIZE })
            memberSpecBtn:SetPoint("BOTTOMRIGHT", cell, "RIGHT", -MEMBER_HALO_PAD, MEMBER_BTN_STACK_GAP / 2)
            local memberGearBtn = Controls:CreateGlyphButton({ parent = cell, atlas = "GM-icon-settings",
                tooltip = "Options", size = MEMBER_BTN_SIZE, glyphScale = MEMBER_GEAR_GLYPH_SCALE })
            memberGearBtn:SetPoint("TOPRIGHT", memberSpecBtn, "BOTTOMRIGHT", 0, -MEMBER_BTN_STACK_GAP)

            -- IsMouseOver covers children, so the pointer on either button still
            -- reads as over the cell. Cells never overlap, so two members cannot
            -- light at once and no frame-level ordering is needed.
            local UpdateHover = function()
                local SpecFlyout = addon.UI.ScootAuraSpecFlyout
                local GearFlyout = addon.UI.ScootAuraGearFlyout
                local over = not Drag.active
                    and (cell:IsMouseOver()
                        or (SpecFlyout and SpecFlyout.IsOpenFor(cell))
                        or (GearFlyout and GearFlyout.IsOpenFor(cell))
                        or false)
                haloBg:SetShown(over)
                haloBorder:SetShown(over)
                memberGearBtn:SetShown(over)
                memberSpecBtn:SetShown(over)
                if box.UpdateHover then box.UpdateHover() end
            end
            -- CreateGlyphButton pokes parent.UpdateHover, and the parent is the cell.
            cell.UpdateHover = UpdateHover
            cell:SetScript("OnEnter", UpdateHover)
            cell:SetScript("OnLeave", UpdateHover)
            table.insert(state.hoverables, cell)
            RegisterTriggers("t" .. tostring(memberId), cell, cell, UpdateHover)

            -- Both panels hang off the cell, not the button inside it: a
            -- panel's nub rises 15px, and from either button it would cross
            -- the other one and the spell art. From the cell it clears both.
            -- Only one fly-out is ever open, so each panel's IsOpenFor(cell)
            -- answers for itself.
            memberSpecBtn:SetScript("OnClick", function()
                OpenSpecFlyout(cell, "t", memberId)
            end)
            memberGearBtn:SetScript("OnClick", function()
                OpenGearFlyout(cell, "t", memberId, { gap = MEMBER_GEAR_GAP, inGroup = true })
            end)

            btn:SetScript("OnEnter", function()
                UpdateHover()
                if Drag.active then return end
                -- Owned by the cell, so it opens clear of the button column.
                GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
                GameTooltip:SetText(SAU.DisplayName(tracker), 1, 1, 1)
                GameTooltip:AddLine(TrackerMetaText(tracker), 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
                UpdateHover()
            end)
            btn:SetScript("OnClick", function()
                if ClickGuard() then return end
                if addon.ShowScootAuraEditor then
                    addon.ShowScootAuraEditor(memberId)
                end
            end)
            -- The whole cell drags, the gutter beside the icon included.
            for _, dragFrom in ipairs({ btn, cell }) do
                dragFrom:RegisterForDrag("LeftButton")
                dragFrom:SetScript("OnDragStart", function()
                    BeginDrag(memberId, gid, index, texture, btn)
                end)
            end

            table.insert(icons, { frame = btn, index = index })
        end
    end

    if shown == 0 then
        local hint = box:CreateFontString(nil, "OVERLAY")
        hint:SetFont(theme:GetFont("LABEL"), 11, "")
        hint:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD, -(headerH + 8))
        hint:SetText("Drag trackers here")
        hint:SetTextColor(0.55, 0.55, 0.55, 1)
    end

    local iconRows = math.max(1, math.ceil(shown / perRow))
    box:SetHeight(headerH + iconRows * (MEMBER_CELL_H + ICON_GAP) + BOX_PAD)

    box.UpdateHover = function()
        local SpecFlyout = addon.UI.ScootAuraSpecFlyout
        local GearFlyout = addon.UI.ScootAuraGearFlyout
        local over = not Drag.active
            and (box:IsMouseOver()
                or (GearFlyout and GearFlyout.IsOpenFor(layoutBtn))
                or (SpecFlyout and SpecFlyout.IsOpenFor(specBtn))
                or false)
        specBtn:SetShown(over)
        deleteBtn:SetShown(over)
        layoutBtn:SetShown(over)
        enabledBtn:SetShown(over)
    end
    box:SetScript("OnEnter", box.UpdateHover)
    box:SetScript("OnLeave", box.UpdateHover)
    table.insert(state.hoverables, box)
    RegisterTriggers("g" .. tostring(gid), specBtn, layoutBtn, box.UpdateHover)

    state.dropGroups[gid] = { box = box, zone = zone, icons = icons }
    return box
end

--------------------------------------------------------------------------------
-- Page render
--------------------------------------------------------------------------------

-- Column heading: larger, underlined, centered over its pane.
local function ColumnLabel(pane, text, theme)
    local ar, ag, ab = theme:GetAccentColor()
    local fs = pane:CreateFontString(nil, "OVERLAY")
    fs:SetFont(theme:GetFont("LABEL"), 13, "")
    fs:SetPoint("TOP", pane, "TOP", 0, -4)
    fs:SetText(text)
    fs:SetTextColor(ar, ag, ab, 0.9)
    local underline = pane:CreateTexture(nil, "BORDER")
    underline:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", -4, -3)
    underline:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 4, -3)
    underline:SetHeight(1)
    underline:SetColorTexture(ar, ag, ab, 0.6)
end

-- A dim centered label with its top y below the pane's top: the Not Loaded
-- heading and the placeholder lines share it.
local function DimLabel(pane, y, text, theme)
    local fs = pane:CreateFontString(nil, "OVERLAY")
    fs:SetFont(theme:GetFont("LABEL"), 11, "")
    fs:SetPoint("TOP", pane, "TOP", 0, -y)
    fs:SetText(text)
    local dr, dg, db = theme:GetDimTextColor()
    fs:SetTextColor(dr, dg, db, 1)
    return fs
end

-- Section heading for the Not Loaded block: a hairline rule, then a dim label.
-- Returns the height it consumed.
local function NotLoadedHeading(pane, y, theme)
    local ar, ag, ab = theme:GetAccentColor()
    local rule = pane:CreateTexture(nil, "BORDER")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -(y + NOT_LOADED_TOP_GAP))
    rule:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -(y + NOT_LOADED_TOP_GAP))
    rule:SetColorTexture(ar, ag, ab, 0.25)

    DimLabel(pane, y + NOT_LOADED_TOP_GAP + 10, "Not Loaded", theme)

    return NOT_LOADED_HEADER_H
end

-- Stand-in for an empty block, so a pane holding only grayed records ("None
-- Loaded"), or one the search emptied ("No matches"), reads as a state
-- rather than a rendering gap. Returns the height it consumed.
local function PlaceholderLine(pane, y, text, theme)
    DimLabel(pane, y + NONE_LOADED_TOP_GAP, text, theme)
    return NONE_LOADED_H
end

RenderList = function(panel, scrollContent, corrective)
    if Drag.active then EndDrag(true) end

    -- An open spec or gear fly-out survives the rebuild that its own edit
    -- asked for. Its trigger does not, so it is unpinned here and handed the
    -- replacement once the new rows exist; every re-render path runs through
    -- this bracket, the deferred corrective pass included.
    local SpecFlyout = addon.UI.ScootAuraSpecFlyout
    local specKey = SpecFlyout and SpecFlyout.GetOpenKey() or nil
    if specKey and not SpecFlyout.BeginReanchor() then specKey = nil end
    local GearFlyout = addon.UI.ScootAuraGearFlyout
    local gearKey = GearFlyout and GearFlyout.GetOpenKey() or nil
    if gearKey and not GearFlyout.BeginReanchor() then gearKey = nil end

    panel:ClearContent()

    local SAU = addon.ScootAuras
    local SettingsBuilder = addon.UI.SettingsBuilder
    local contentPane = panel.frame and panel.frame._contentPane

    if not (SAU and SAU.IsModuleActive()) then
        if specKey then SpecFlyout.EndReanchor(nil) end
        if gearKey then GearFlyout.EndReanchor(nil) end
        -- The header widgets belong to the live page alone.
        if contentPane and contentPane._scootAuraImportBtn then
            contentPane._scootAuraImportBtn:Hide()
        end
        if contentPane and contentPane._scootAuraImportFlyout then
            contentPane._scootAuraImportFlyout:Close()
        end
        if contentPane and contentPane._scootAuraSearch then
            contentPane._scootAuraSearch:Hide()
        end
        local builder = SettingsBuilder:CreateFor(scrollContent)
        panel._currentBuilder = builder
        builder:AddDescription(
            "ScootAuras is turned off. Enable it on the Features page, then reload.",
            { color = { 1, 0.82, 0 }, fontSize = 13, topPadding = 8 })
        builder:Finalize()
        return
    end

    state.active = true
    state.textRows = {}
    state.panel = panel
    state.scrollContent = scrollContent
    panel._scootAurasCleanup = function() Cleanup(panel) end

    local theme = addon.UI.Theme
    local ar, ag, ab = theme:GetAccentColor()
    local totalW = scrollContent:GetWidth() or 600

    -- Header widgets first: the how-to line's width reads the Import
    -- button's, which the button control sets at build.
    EnsureHeaderWidgets(contentPane)
    if contentPane and contentPane._scootAuraImportBtn then
        contentPane._scootAuraImportBtn:Show()
    end
    if contentPane and contentPane._scootAuraSearch then
        contentPane._scootAuraSearch:Show()
    end

    -- The how-to line rides the page header as its subtitle: gray like the
    -- row meta text, hung under the title at an explicit width that ends
    -- before the search box, so it wraps instead of running under it. The
    -- stock header leaves 26px under the title, two lines at most, so the
    -- header grows to what the wrapped line needs. Cleanup restores the
    -- stock look through UIPanel:ResetHeaderSubtitle before another page
    -- reuses the FontString; the flag keeps the theme subscription from
    -- recoloring it to accent.
    if contentPane and contentPane._headerSubtitle and contentPane._header then
        local sub = contentPane._headerSubtitle
        sub:SetText(
            "Auras are shared by every character on your account and load in the specializations you pick. Click a tracker to edit it. Drag trackers into groups; drag a group's icons to reorder or remove them. Position frames in Edit Mode.")
        sub:ClearAllPoints()
        sub:SetPoint("TOPLEFT", contentPane._header, "TOPLEFT", HEADER_SIDE, -SUBTITLE_TOP)
        sub:SetFont(theme:GetFont("LABEL"), 10, "")
        sub:SetJustifyH("LEFT")
        sub:SetJustifyV("TOP")
        sub:SetWordWrap(true)
        sub:SetTextColor(0.55, 0.55, 0.55, 1)
        sub:SetHeight(0)
        sub:SetWidth(SubtitleWidth(contentPane))
        contentPane._header:SetHeight(HeaderHeightFor(contentPane))
        contentPane._headerSubtitleCustom = true
        sub:Show()
    end

    -- A resize moves the width the how-to line wraps to and the widths the
    -- rows and boxes wrap to; rebuild once the drag settles.
    if contentPane then
        contentPane._onResize = function()
            addon.UI.Controls.Debounce(RESIZE_DEBOUNCE_KEY, 0.2, Refresh)
        end
    end

    local query = SearchQuery(contentPane)
    local searching = query ~= ""

    -- Pane split: fixed offsets from the measured content width, divider
    -- between them with clearance on both sides.
    local leftW = math.floor(totalW * LEFT_FRACTION)
    local rightX = leftW + DIVIDER_CLEAR_R

    local leftPane = CreateFrame("Frame", nil, scrollContent)
    leftPane:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, 0)
    leftPane:SetPoint("TOPRIGHT", scrollContent, "TOPLEFT", leftW - DIVIDER_CLEAR_L, 0)
    state.leftPane = leftPane
    table.insert(state.rows, leftPane)

    -- The tracker list takes a drop as one target: it is ordered by name, so
    -- there is no position to aim at and no insertion line to draw.
    state.leftDropZone = CreateDropZone(leftPane)

    local rightPane = CreateFrame("Frame", nil, scrollContent)
    rightPane:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", rightX, 0)
    rightPane:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, 0)
    table.insert(state.rows, rightPane)

    ColumnLabel(leftPane, "Individual Auras", theme)
    ColumnLabel(rightPane, "Groups", theme)

    -- Left pane: ungrouped trackers. Rows are no longer a fixed height: the
    -- meta line wraps, so each row reports what it needs.
    local leftRowW = math.max(80, leftW - DIVIDER_CLEAR_L)
    local yL = COL_LABEL_H
    local loadedT, unloadedT = {}, {}
    for _, item in ipairs(SAU.SortedTrackers()) do
        if item.tracker.groupId == nil
            and (not searching or TrackerMatches(SAU, item.tracker, query)) then
            local bucket = SAU.IsTrackerActive(item.id, item.tracker) and loadedT or unloadedT
            table.insert(bucket, item)
        end
    end

    local function AddTrackerRows(items, loaded)
        for _, item in ipairs(items) do
            local row = CreateTrackerRow(leftPane, item.id, item.tracker, leftRowW, loaded)
            row:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, -yL)
            row:SetPoint("TOPRIGHT", leftPane, "TOPRIGHT", 0, -yL)
            table.insert(state.rows, row)
            table.insert(state.textRows, row)
            yL = yL + row:GetHeight()
        end
    end

    -- Under a search the "None Loaded" stand-in is skipped: it describes the
    -- store, not the query. A pane the search emptied says so instead.
    if #loadedT > 0 then
        AddTrackerRows(loadedT, true)
    elseif not searching then
        yL = yL + PlaceholderLine(leftPane, yL, "None Loaded", theme)
    end
    if #unloadedT > 0 then
        yL = yL + NotLoadedHeading(leftPane, yL, theme)
        AddTrackerRows(unloadedT, false)
    elseif searching and #loadedT == 0 then
        yL = yL + PlaceholderLine(leftPane, yL, "No matches", theme)
    end

    -- Right pane: group boxes. Widths come from the content frame (pane rects
    -- resolve at end of frame, too late for the icon wrap).
    local rightW = math.max(120, totalW - rightX)
    local yR = COL_LABEL_H
    local loadedG, unloadedG = {}, {}
    local keepByGroup = {}   -- [gid] = the members the search matched
    for _, item in ipairs(SAU.SortedGroups()) do
        local match = searching and GroupMatch(SAU, item.id, item.group, query) or nil
        if not match or match.shown then
            keepByGroup[item.id] = match and match.keep or nil
            local bucket = SAU.IsGroupActive(item.id, item.group) and loadedG or unloadedG
            table.insert(bucket, item)
        end
    end

    local function AddGroupBoxes(items, loaded)
        for _, item in ipairs(items) do
            local box = CreateGroupBox(rightPane, item.id, item.group, rightW, loaded, keepByGroup[item.id])
            box:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 0, -yR)
            box:SetPoint("TOPRIGHT", rightPane, "TOPRIGHT", 0, -yR)
            table.insert(state.rows, box)
            -- A box with a spec line joins the deferred re-measure.
            if box._specFS then table.insert(state.textRows, box) end
            yR = yR + box:GetHeight() + BOX_GAP
        end
    end

    if #loadedG > 0 then
        AddGroupBoxes(loadedG, true)
    elseif not searching then
        yR = yR + PlaceholderLine(rightPane, yR, "None Loaded", theme)
    end
    if #unloadedG > 0 then
        yR = yR + NotLoadedHeading(rightPane, yR, theme)
        AddGroupBoxes(unloadedG, false)
    elseif searching and #loadedG == 0 then
        yR = yR + PlaceholderLine(rightPane, yR, "No matches", theme)
    end

    -- Content height: enough for the longer list plus the add buttons, but
    -- never shorter than the viewport, so the add buttons and the divider sit
    -- at the pane bottom even when the lists are short.
    local scrollFrame = scrollContent:GetParent()
    local viewH = (scrollFrame and scrollFrame:GetHeight()) or 0
    local contentH = math.max(yL, yR) + ADD_ROW_H + 16
    if viewH > 0 then
        contentH = math.max(contentH, viewH - 2)
    end
    scrollContent:SetHeight(contentH)
    leftPane:SetHeight(contentH)
    rightPane:SetHeight(contentH)

    -- Add buttons, statically centered at the bottom of their panes.
    local addAura = CreateAddRow(leftPane, "+ Add Aura", function()
        if addon.ShowScootAuraEditor then addon.ShowScootAuraEditor(nil) end
    end)
    addAura:SetPoint("BOTTOMLEFT", leftPane, "BOTTOMLEFT", 0, 4)
    addAura:SetPoint("BOTTOMRIGHT", leftPane, "BOTTOMRIGHT", 0, 4)
    table.insert(state.rows, addAura)

    local addGroup = CreateAddRow(rightPane, "+ Add Group", function()
        if SAU.CreateGroup(nil) then Refresh() end
    end)
    addGroup:SetPoint("BOTTOMLEFT", rightPane, "BOTTOMLEFT", 0, 4)
    addGroup:SetPoint("BOTTOMRIGHT", rightPane, "BOTTOMRIGHT", 0, 4)
    table.insert(state.rows, addGroup)

    -- Divider, full pane height regardless of list length.
    local sep = CreateFrame("Frame", nil, scrollContent)
    sep:SetSize(1, contentH)
    sep:SetPoint("TOP", scrollContent, "TOPLEFT", leftW, 0)
    local sepTex = sep:CreateTexture(nil, "BORDER")
    sepTex:SetAllPoints()
    sepTex:SetColorTexture(ar, ag, ab, 0.2)
    table.insert(state.rows, sep)

    -- Hand the fly-out its rebuilt trigger. A record that moved between the
    -- Loaded and Not Loaded blocks has a new button at a new height, so the
    -- panel jumps with it; one that is gone from the page, deleted or
    -- filtered out by the search, closes it.
    if specKey then
        local entry = state.triggers[specKey]
        SpecFlyout.EndReanchor(entry and entry.spec, entry and entry.reveal)
    end
    if gearKey then
        local entry = state.triggers[gearKey]
        GearFlyout.EndReanchor(entry and entry.gear, entry and entry.reveal)
    end

    -- The shared content scrollbar re-measures on the next frame. The first
    -- render after a page switch can also read a stale viewport height (the
    -- scroll frame re-anchors in the same tick, and the header above it is
    -- resized in this one); one corrective re-render pins the add buttons to
    -- the true bottom. The viewport height depends on the header's width and
    -- the how-to line, never on the list, so this cannot loop.
    C_Timer.After(0, function()
        if contentPane and contentPane._scrollbar and contentPane._scrollbar.Sync then
            contentPane._scrollbar:Sync()
        end
        if state.active and state.scrollContent == scrollContent then
            local vh = (scrollFrame and scrollFrame:GetHeight()) or 0
            if vh > 0 and math.abs(vh - viewH) > 1 then
                RenderList(panel, scrollContent, corrective)
                return
            end
            -- A cold font measures short. Now that the rows and boxes have
            -- rendered once, re-measure and restack if any wants more room.
            -- One corrective pass only: the flag rides the recursion.
            if corrective then return end
            for _, row in ipairs(state.textRows) do
                local moved = false
                if row._name and row._meta then
                    moved = math.abs(MeasuredRowHeight(row._name, row._meta) - (row:GetHeight() or 0)) > 1
                elseif row._specFS then
                    moved = MeasuredSpecHeight(row._specFS) ~= row._specH
                end
                if moved then
                    RenderList(panel, scrollContent, true)
                    return
                end
            end
            -- The how-to line measured cold, or before the header had a rect.
            -- Lay it out again; when the header's height moves, the viewport
            -- moves with it a frame later, so the rebuild waits for that
            -- frame and reads the settled height.
            if contentPane and contentPane._headerSubtitleCustom and contentPane._header then
                local header, sub = contentPane._header, contentPane._headerSubtitle
                local wantW = SubtitleWidth(contentPane)
                if math.abs(wantW - (sub:GetWidth() or 0)) > 1 then sub:SetWidth(wantW) end
                local wantH = HeaderHeightFor(contentPane)
                if math.abs(wantH - (header:GetHeight() or 0)) > 1 then
                    header:SetHeight(wantH)
                    C_Timer.After(0, function()
                        if state.active and state.scrollContent == scrollContent then
                            RenderList(panel, scrollContent, true)
                        end
                    end)
                end
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Registration + external refresh hook (the editor pokes this)
--------------------------------------------------------------------------------

addon.ScootAurasUI = addon.ScootAurasUI or {}
function addon.ScootAurasUI.RefreshList()
    Refresh()
end

-- The three fly-outs outlive the page and would strand over the world when
-- the settings window hides under them (a /scoot toggle, the combat
-- auto-hide); the window's OnHide calls this.
function addon.ScootAurasUI.CloseFlyouts()
    local SpecFlyout = addon.UI.ScootAuraSpecFlyout
    if SpecFlyout then SpecFlyout.Close() end
    local GearFlyout = addon.UI.ScootAuraGearFlyout
    if GearFlyout then GearFlyout.Close() end
    local contentPane = state.panel and state.panel.frame and state.panel.frame._contentPane
    local import = contentPane and contentPane._scootAuraImportFlyout
    if import then import:Close() end
end

addon.UI.SettingsPanel:RegisterRenderer("scootAurasList", function(panel, scrollContent)
    RenderList(panel, scrollContent)
end)
