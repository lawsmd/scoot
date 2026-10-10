-- saved.lua - the saved searches: a tray under the window's panels on the
-- home page and the search view, a band per saved search with its title
-- over the filter in columns of four, an x that deletes it, and a click
-- that puts the filters back and searches; with it the Save Search button's
-- logic (the button stands on the search panel, search.lua). The list, the
-- capture and the summary are the component's
-- (core/components/groupfinder/saved.lua).
--
-- A click writes the saved Dungeons filter and language filter to the
-- client, selects the category on Blizzard's hidden panel as a category row
-- does, and opens the search view as Find a Group does, with one step
-- between the category and the search: the saved activity goes into the
-- hosted box (GF.Saved.Fill). The box takes no text from addon code, so a
-- saved search with text runs as a paste: Scoot's own box holds the text
-- highlighted for the player's copy, focus moves to Blizzard's box for the
-- paste, and the search runs on the paste's key release. The row shows the
-- keys in place of its columns, the next one filled.
local addonName, addon = ...

local GF = addon.GroupFinder
local UI = GF.UI
local LAYOUT = UI.LAYOUT
local Saved = GF.Saved

local function Controls()
    return addon.UI.Controls
end

local function Theme()
    return addon.UI.Theme
end

local function M()
    return addon.UI.Controls.Metrics()
end

-- The red the result rows use for a group off the filter
local RED = { 0.85, 0.2, 0.2 }

local Tray = {}
UI.Saved = Tray

--------------------------------------------------------------------------------
-- Save Search: the reason it is off, and the save
--------------------------------------------------------------------------------

function Tray:SaveBlock()
    if not Saved then return "Saved searches are not loaded" end
    if Saved.Count() >= Saved.MAX then
        return string.format("%d saved searches already. Delete one to save another.", Saved.MAX)
    end
    local live = Saved.Capture()
    if not live then return "Nothing to save yet" end
    local key = Saved.Key(live)
    for _, entry in ipairs(Saved.List()) do
        if Saved.Key(entry) == key then return "This search is already saved" end
    end
    return nil
end

-- The save raises the saved topic, which shows the tray
function Tray:SaveCurrent()
    if not Saved or self:SaveBlock() then return false end
    local entry = Saved.Capture()
    return entry ~= nil and Saved.Add(entry)
end

--------------------------------------------------------------------------------
-- The paste: a saved search's text goes into Blizzard's box only by the
-- player's keys. Steps: "copy" (Scoot's box holds the text highlighted),
-- "paste" (Blizzard's box has focus), "searching" (the paste's text change
-- ran the search), "enter" (that search was refused; Blizzard's own Enter
-- runs it).
--------------------------------------------------------------------------------

local function ModifierName()
    return (IsMacClient and IsMacClient()) and "Cmd" or "Ctrl"
end

-- The paste's step when it runs on this row, else nil
function Tray:PasteStep(key)
    local paste = self.paste
    if paste and paste.key == key then return paste.step end
    return nil
end

local function Redraw()
    if Tray.panel and Tray.panel:IsShown() then Tray.panel:Refresh() end
end

-- The copy box: Scoot's own, so it takes the text. It stays shown, since a
-- hidden edit box gives up its focus; the engine draws its selection
-- without the frame's alpha, so the highlight and the text are clear and
-- the box sits in a one-pixel holder that clips whatever else it draws
function Tray:CopyBox()
    if self.copyBox then return self.copyBox end
    local parent = self.panel or UIParent
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(1, 1)
    holder:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    holder:SetClipsChildren(true)
    holder:SetAlpha(0)
    local box = CreateFrame("EditBox", nil, holder)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetSize(160, 20)
    box:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    box:SetTextColor(0, 0, 0, 0)
    box:SetHighlightColor(0, 0, 0, 0)
    box:EnableMouse(false)
    box._holder = holder
    box:SetScript("OnKeyDown", function(_, key)
        if key ~= "C" or not (IsControlKeyDown() or (IsMetaKeyDown and IsMetaKeyDown())) then return end
        -- The copy is the engine's, on this same key; the move waits a frame
        C_Timer.After(0, function() Tray:ToPaste() end)
    end)
    box:SetScript("OnEscapePressed", function() Tray:EndPaste() end)
    box:SetScript("OnEditFocusLost", function()
        if Tray.paste and Tray.paste.step == "copy" and not Tray.moving then Tray:EndPaste() end
    end)
    -- The text is the saved text; a key that changes it puts it back
    box:SetScript("OnTextChanged", function(b, userInput)
        local paste = Tray.paste
        if userInput and paste then
            b:SetText(paste.clip)
            b:HighlightText()
        end
    end)
    self.copyBox = box
    return box
end

function Tray:StartPaste(sp, entry, want, clip)
    local box = self:CopyBox()
    self.paste = { key = Saved.Key(entry), sp = sp, want = want, clip = clip, text = entry.text, step = "copy" }
    box._holder:Show()
    box:Show()
    box:SetText(clip)
    box:SetFocus()
    box:HighlightText()
    Redraw()
end

function Tray:EndPaste(quiet)
    local box = self.copyBox
    self.paste = nil
    if box and box:HasFocus() then
        self.moving = true
        box:ClearFocus()
        self.moving = false
    end
    if box then box:Hide() end
    if not quiet then Redraw() end
end

-- After the copy: focus to Blizzard's box, the cursor after the activity's
-- name, for the paste
function Tray:ToPaste()
    local paste = self.paste
    if not (paste and paste.step == "copy") then return end
    local blizzard = paste.sp and paste.sp.SearchBox
    if not blizzard then return self:EndPaste() end
    self.moving = true
    self.copyBox:ClearFocus()
    self.copyBox:Hide()
    self.moving = false
    paste.step = "paste"
    self:HookKeyUp(blizzard)
    pcall(blizzard.SetFocus, blizzard)
    local current = Saved.BoxText(blizzard) or ""
    pcall(blizzard.SetCursorPosition, blizzard, #current)
    Redraw()
end

-- The search after the paste. The text change inside Ctrl+V does not count
-- as the player's input for Search (blocked when tried), so the search runs
-- from the key's release; after one refusal in a session the row asks for
-- Enter at once
function Tray:RunPasteSearch()
    local paste = self.paste
    if not (paste and paste.step == "pasted") then return end
    if Saved.autoSearch == "blocked" or not (GF.SearchAllowed() and LFGListSearchPanel_DoSearch) then
        paste.step = "enter"
        Redraw()
        return
    end
    paste.step = "searching"
    paste.lastSearchAt = GF.state.lastSearchAt
    LFGListSearchPanel_DoSearch(paste.sp)
    if self.paste == paste and paste.step == "searching" then
        C_Timer.After(2, function()
            if Tray.paste == paste and paste.step == "searching" then
                Saved.autoSearch = "timeout"
                paste.step = "enter"
                Redraw()
            end
        end)
    end
    Redraw()
end

-- Blizzard's box changed: when it reads the whole saved text, the paste
-- landed, and the search waits for the key's release
function Tray:CheckPaste()
    local paste = self.paste
    if not (paste and paste.step == "paste") then return end
    local blizzard = paste.sp and paste.sp.SearchBox
    local text = blizzard and Saved.BoxText(blizzard)
    if not text or text ~= paste.want then return end
    paste.step = "pasted"
    if Saved.autoSearch == "blocked" then
        return self:RunPasteSearch()
    end
    -- A release that never reaches the box leaves Enter to the player
    C_Timer.After(1, function()
        if Tray.paste == paste and paste.step == "pasted" then
            paste.step = "enter"
            Redraw()
        end
    end)
end

-- The release of the paste's keys, on Blizzard's box
function Tray:HookKeyUp(blizzard)
    if self.keyUpHooked == blizzard then return end
    self.keyUpHooked = blizzard
    blizzard:HookScript("OnKeyUp", function()
        if Tray.paste and Tray.paste.step == "pasted" then Tray:RunPasteSearch() end
    end)
end

-- The search from the paste was refused: the spinner and the cooldown go
-- back as they were, and Blizzard's own Enter runs the search
addon.Events.On("GroupFinderSaved", "ADDON_ACTION_BLOCKED", function(_, blockedAddon)
    local paste = Tray.paste
    if not (paste and paste.step == "searching") then return end
    if blockedAddon ~= addonName then return end
    Saved.autoSearch = "blocked"
    paste.step = "enter"
    GF.state.searching = false
    GF.state.lastSearchAt = paste.lastSearchAt or 0
    GF.Notify("searching")
    Redraw()
end)

--------------------------------------------------------------------------------
-- The replay
--------------------------------------------------------------------------------

-- The box takes the activity's name from the C side; a saved search with
-- text waits for the paste, with the text as the box's prompt while it is
-- empty
function Tray:FillBox(sp, entry)
    local box = sp and sp.SearchBox
    if not box then return true end
    local prefix, want, clip = Saved.Fill(box, entry.activityID, entry.text)
    if clip == "" then return true end
    if prefix == "" and UI.Search and UI.Search.SetGhost then
        UI.Search.SetGhost(sp, entry.text)
    end
    self:StartPaste(sp, entry, want, clip)
    return false
end

function Tray:Run(entry)
    if not (entry and UI:IsShown() and Saved) then return false end
    if not GF.SearchAllowed() then return false end
    self:EndPaste(true)
    local lf = LFGListFrame
    local cs = lf and lf.CategorySelection
    if not (cs and LFGListCategorySelection_SelectCategory and UI.Search) then return false end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)

    -- The filters first: the search reads both off the client. A saved
    -- dungeon list keeps to the groups the client lists now
    local liveSet = Saved.LiveGroupSet()
    if C_LFGList.SaveAdvancedFilter then
        local advanced = Saved.CopyAdvanced(entry.advanced)
        advanced.activities = Saved.LiveActivities(advanced.activities, liveSet)
        C_LFGList.SaveAdvancedFilter(advanced)
    end
    if entry.languages and C_LFGList.SaveLanguageSearchFilter then
        C_LFGList.SaveLanguageSearchFilter(Saved.CopyLanguages(entry.languages) or {})
    end

    -- The category on Blizzard's panel, which the search reads for the
    -- advanced filter and the window for the filter's mode; a category
    -- with no activities now is deselected by Blizzard's own update
    LFGListCategorySelection_SelectCategory(cs, entry.categoryID, entry.filters or 0)
    if GF.plainNumber(cs.selectedCategory) ~= entry.categoryID then
        self.blockedKey = Saved.Key(entry)
        if self.panel then self.panel:Refresh() end
        return false
    end
    self.blockedKey = nil
    return UI.Search:Open(entry.categoryID, entry.filters or 0, nil, function(sp)
        return self:FillBox(sp, entry)
    end)
end

--------------------------------------------------------------------------------
-- The rows
--------------------------------------------------------------------------------

-- The flyout's nub: a flat triangle pointing up in its image, turned to
-- point right
local TRIANGLE = addon.MediaPath .. "media\\textures\\flyout-nub"
local TRIANGLE_RIGHT = -math.pi / 2

local function PaintRow(row)
    local r, g, b, a = row._backdrop:LabelColor()
    row._name:SetTextColor(r, g, b, a or 1)
end

-- Each set of the filter in columns of colLines lines
local function Chunks(columns)
    local L = LAYOUT.saved
    local chunks = {}
    for _, lines in ipairs(columns or {}) do
        for first = 1, #lines, L.colLines do
            local chunk = {}
            for i = first, math.min(first + L.colLines - 1, #lines) do chunk[#chunk + 1] = lines[i] end
            chunks[#chunks + 1] = chunk
        end
    end
    return chunks
end

local function KeyTag(parent, text)
    local C = Controls()
    local L = LAYOUT.saved
    local tag = C.CreateTag(parent, { text = text, padX = L.keyPadX })
    Theme():ApplyFont(tag._text, "label", L.keySize)
    tag:SetText(text)
    tag:SetHeight(L.keyHeight)
    return tag
end

-- Three triangles in a row. While the next key is to their right, a light
-- runs through them left to right on a loop: each brightens in turn, and
-- every loop is the same length so the three stay in step
local function Triangles(parent)
    local L = LAYOUT.saved
    local group = CreateFrame("Frame", nil, parent)
    group:SetSize(3 * L.triSize + 2 * L.triGap, L.triSize)
    group._tris = {}
    for i = 1, 3 do
        local tri = group:CreateTexture(nil, "ARTWORK")
        tri:SetTexture(TRIANGLE)
        tri:SetRotation(TRIANGLE_RIGHT)
        tri:SetSize(L.triSize, L.triSize)
        tri:SetPoint("LEFT", group, "LEFT", (i - 1) * (L.triSize + L.triGap), 0)
        local anim = tri:CreateAnimationGroup()
        anim:SetLooping("REPEAT")
        local up = anim:CreateAnimation("Alpha")
        up:SetFromAlpha(L.triDim)
        up:SetToAlpha(1)
        up:SetDuration(L.chaseUp)
        up:SetStartDelay((i - 1) * L.chaseStep)
        up:SetOrder(1)
        local down = anim:CreateAnimation("Alpha")
        down:SetFromAlpha(1)
        down:SetToAlpha(L.triDim)
        down:SetDuration(L.chaseDown)
        down:SetEndDelay((3 - i) * L.chaseStep + L.chaseRest)
        down:SetOrder(2)
        tri._anim = anim
        group._tris[i] = tri
    end

    -- "chase", "lit", or "dim"
    function group:SetState(state)
        local r, g, b = Theme():GetAccentColor()
        for _, tri in ipairs(self._tris) do
            tri:SetVertexColor(r, g, b, 1)
            if state == "chase" then
                tri:SetAlpha(L.triDim)
                if not tri._anim:IsPlaying() then tri._anim:Play() end
            else
                tri._anim:Stop()
                tri:SetAlpha(state == "lit" and 1 or L.triDim)
            end
        end
    end
    return group
end

local function CreateRow(panel, row)
    local C = Controls()
    local L = LAYOUT.saved
    local A = LAYOUT.search.action
    local padX = (M().listRow or {}).padX or 8
    row._padX = padX
    row._right = padX + A.size + A.gap

    -- The title over the line under it, centred on the row; a title wider
    -- than its room wraps
    row._title = CreateFrame("Frame", nil, row)
    row._title:SetPoint("LEFT", row, "LEFT", padX, 0)
    row._title:SetSize(1, 1)

    row._name = UI.PrimaryText(row._title, "label")
    row._name:SetPoint("TOPLEFT", row._title, "TOPLEFT", 0, 0)
    row._name:SetWordWrap(true)
    row._name:SetMaxLines(2)

    row._sub = UI.DimText(row._title, "desc", L.subSize)
    row._sub:SetPoint("TOPLEFT", row._name, "BOTTOMLEFT", 0, -L.subGap)
    row._sub:SetWordWrap(true)
    row._sub:SetMaxLines(2)

    -- The filter's columns: one string per line in a frame of their own,
    -- which Layout scales down when the smallest size still runs past the
    -- room
    row._block = CreateFrame("Frame", nil, row)
    row._block:SetPoint("TOPLEFT", row, "TOPLEFT", padX, 0)
    row._block:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -row._right, 0)
    row._cols = CreateFrame("Frame", nil, row._block)
    row._cols:SetPoint("LEFT", row._block, "LEFT", 0, 0)
    row._cols:SetSize(1, 1)
    row._lines = addon.Pool.NewIndexed(function()
        local fs = UI.DimText(row._cols, "desc", L.colSize)
        fs:SetWordWrap(false)
        return fs
    end, function(fs) fs:Hide() end)

    -- The paste's keys, in the columns' place and centred on it
    local area = CreateFrame("Frame", nil, row)
    area:SetAllPoints(row._block)
    local keys = CreateFrame("Frame", nil, area)
    keys:SetPoint("CENTER", area, "CENTER", 0, 0)
    keys:SetSize(1, L.keyHeight)
    keys:Hide()
    row._keys = keys
    local mod = ModifierName()
    keys._copy = KeyTag(keys, mod .. " + C")
    keys._copy:SetPoint("LEFT", keys, "LEFT", 0, 0)
    keys._tris1 = Triangles(keys)
    keys._tris1:SetPoint("LEFT", keys._copy, "RIGHT", L.keyGap, 0)
    keys._paste = KeyTag(keys, mod .. " + V")
    keys._paste:SetPoint("LEFT", keys._tris1, "RIGHT", L.keyGap, 0)
    keys._tris2 = Triangles(keys)
    keys._tris2:SetPoint("LEFT", keys._paste, "RIGHT", L.keyGap, 0)
    keys._enter = KeyTag(keys, "Enter")
    keys._enter:SetPoint("LEFT", keys._tris2, "RIGHT", L.keyGap, 0)

    row._delete = C:CreateButton({
        parent = row, text = "x", width = A.size, height = A.size, fontSize = A.font,
        borderWidth = A.border, borderAlpha = A.borderAlpha, labelAlpha = A.labelAlpha,
        onClick = function() panel:Delete(row._index) end,
        tooltip = "Delete this saved search",
    })
    row._delete:SetPoint("RIGHT", row, "RIGHT", -padX, 0)
end

-- The title and the line under it, as wide as the wider draws on one line
local function TitleWidth(row)
    local w = math.ceil(row._name:GetUnboundedStringWidth() or 0)
    if row._sub:IsShown() then
        w = math.max(w, math.ceil(row._sub:GetUnboundedStringWidth() or 0))
    end
    return w
end

-- The title and the line under it in width w, the frame as tall as they
-- draw so the pair centres on the row
local function SizeTitle(row, w)
    local L = LAYOUT.saved
    row._name:SetWidth(w)
    row._sub:SetWidth(w)
    local h = row._name:GetStringHeight() or 0
    if row._sub:IsShown() then h = h + L.subGap + (row._sub:GetStringHeight() or 0) end
    row._title:SetSize(w, math.max(1, math.ceil(h)))
end

-- The filter's lines into their strings, a column per chunk
local function FillColumns(row)
    local strings = {}
    local n = 0
    for c, chunk in ipairs(row._chunks or {}) do
        strings[c] = {}
        for i, line in ipairs(chunk) do
            n = n + 1
            local fs = row._lines:Get(n)
            fs:SetText(line)
            fs:Show()
            strings[c][i] = fs
        end
    end
    row._lines:HideFrom(n + 1)
    row._strings = strings
end

-- The columns' widths at a font size, and their total with the gaps
local function MeasureColumns(row, size)
    local L = LAYOUT.saved
    local theme = Theme()
    local widths, total = {}, 0
    for c, column in ipairs(row._strings or {}) do
        local w = 0
        for _, fs in ipairs(column) do
            theme:ApplyFont(fs, "desc", size)
            w = math.max(w, fs:GetUnboundedStringWidth() or 0)
        end
        widths[c] = math.ceil(w)
        total = total + widths[c] + (c > 1 and L.colGap or 0)
    end
    return widths, total
end

-- The room the columns have right of a title titleW wide
local function ColumnRoom(row, titleW)
    return (row:GetWidth() or 0) - row._padX - titleW - LAYOUT.saved.titleGap - row._right
end

-- The title in titleW, or the whole row when it has no filter; the columns
-- from titleGap right of it, each as wide as its widest line, centred on
-- the row. A size too wide for the room steps down to colMinSize, and past
-- that the columns' frame scales to the room, so every line shows whole
local function Layout(row, titleW)
    local L = LAYOUT.saved
    local strings = row._strings or {}
    if #strings == 0 then
        titleW = math.max(titleW, (row:GetWidth() or 0) - row._padX - row._right)
    end
    SizeTitle(row, math.max(1, titleW))
    local left = row._padX + titleW + L.titleGap
    row._block:ClearAllPoints()
    row._block:SetPoint("TOPLEFT", row, "TOPLEFT", left, 0)
    row._block:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -row._right, 0)
    local room = ColumnRoom(row, titleW)

    local widths, total
    for size = L.colSize, L.colMinSize, -1 do
        widths, total = MeasureColumns(row, size)
        if room <= 1 or total <= room then break end
    end

    local lines = 0
    local x = 0
    for c, column in ipairs(strings) do
        lines = math.max(lines, #column)
        for i, fs in ipairs(column) do
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", row._cols, "TOPLEFT", x, -(i - 1) * L.lineHeight)
            fs:SetWidth(widths[c] + 1)
        end
        x = x + widths[c] + L.colGap
    end
    row._cols:SetSize(math.max(1, total + 1), math.max(1, lines * L.lineHeight))
    row._cols:SetScale((room > 1 and total + 1 > room) and room / (total + 1) or 1)
end

-- The next key filled. The triangles before it run their light toward it
-- once the first key is done, and keep running while the search goes out,
-- so the keys stand unchanged until the results take them away. The group
-- centres on the two keys; Enter, when Blizzard's own Enter has to run the
-- search, hangs off to the right
local function PaintKeys(keys, step)
    local L = LAYOUT.saved
    local enter = step == "enter"
    local pasting = step == "paste" or step == "pasted" or step == "searching"
    keys._copy:SetFilled(step == "copy")
    keys._paste:SetFilled(pasting)
    keys._tris1:SetState(pasting and "chase" or (step == "copy" and "dim" or "lit"))
    keys._tris2:SetShown(enter)
    keys._tris2:SetState(enter and "chase" or "dim")
    keys._enter:SetShown(enter)
    keys._enter:SetFilled(enter)
    local width = keys._copy:GetWidth() + L.keyGap + keys._tris1:GetWidth() + L.keyGap + keys._paste:GetWidth()
    keys:SetWidth(math.max(1, width))
end

-- The title over its difficulty and category, and right of them the
-- filter's columns or, while this row's paste runs, its keys; a row inside
-- the search cooldown stands disabled, as Find a Group does. The tray's
-- Refresh lays the rows out together
local function RenderRow(row, item)
    local theme = Theme()
    local L = LAYOUT.saved
    local d = item.describe
    row._name:SetText(d.title or "")
    theme:ApplyFont(row._name, "label")
    row._sub:SetText(d.sub or "")
    theme:ApplyFont(row._sub, "desc", L.subSize)
    row._sub:SetShown(d.sub ~= nil)

    local step = Tray:PasteStep(item.key)
    local allowed = GF.SearchAllowed()
    row._chunks = item.chunks
    row._keys:SetShown(step ~= nil)
    row._block:SetShown(step == nil)
    if step then
        PaintKeys(row._keys, step)
    else
        row._block:SetAlpha(allowed and 1 or LAYOUT.search.staleAlpha)
    end
    row._sub:SetAlpha(allowed and 1 or LAYOUT.search.staleAlpha)
    row._backdrop:SetDisabled(not allowed and not step)
    PaintRow(row)
end

--------------------------------------------------------------------------------
-- The tray
--------------------------------------------------------------------------------

local function Build(tray)
    local C = Controls()
    local L = LAYOUT.saved
    local panel = CreateFrame("Frame", nil, tray)
    panel:SetAllPoints(tray)
    Tray.panel = panel

    -- The box: a border round the caption and the rows, as the results
    -- have one, its foot boxBottom off the window's
    local m = M().collapsible or {}
    local box = CreateFrame("Frame", nil, panel)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", LAYOUT.panel.boxX, -L.boxTop)
    box:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LAYOUT.panel.boxX, L.boxBottom)
    box._border = C.CreateBorder(box, {
        thickness = m.borderWidth or 1,
        alpha = m.borderAlpha or 0.6,
        corners = "overlap",
    })
    panel._box = box

    panel._caption = UI.MakeCaption(box, "Saved searches")
    panel._caption:SetJustifyH("CENTER")
    panel._caption:SetPoint("TOP", box, "TOP", 0, -L.captionTop)

    local list = C.CreateScrollList({
        parent = box,
        rowHeight = L.rowHeight,
        scrollBar = false,
        gutter = false,
        createRow = function(row) CreateRow(panel, row) end,
        render = function(row, item) RenderRow(row, item) end,
        onSelect = function(item) panel:Select(item) end,
        onEnter = function(item, _, row)
            panel:ShowTooltip(row, item)
            PaintRow(row)
        end,
        onLeave = function(_, _, row)
            GameTooltip:Hide()
            PaintRow(row)
        end,
    })
    list.frame:SetPoint("TOPLEFT", box, "TOPLEFT", L.boxPad, -(L.captionTop + L.captionHeight + L.captionGap))
    list.frame:SetPoint("RIGHT", box, "RIGHT", -L.boxPad, 0)
    list.frame:SetHeight(1)
    panel._list = list

    -- Every row's title in one width, so the columns start at one edge
    -- down the tray: the widest title, up to titleShare of the row, and
    -- narrower still where a row's columns at colMinSize need the room. A
    -- title past the width wraps; it never goes under titleMin
    function panel:LayoutRows()
        local count = #(self._items or {})
        local natural = 0
        local cap = math.floor((list.frame:GetWidth() or 0) * L.titleShare)
        for i = 1, count do
            local row = list:GetRow(i)
            if row then
                natural = math.max(natural, TitleWidth(row))
                FillColumns(row)
                if #row._strings > 0 and (row:GetWidth() or 0) > 1 then
                    local _, total = MeasureColumns(row, L.colMinSize)
                    local grant = math.floor(ColumnRoom(row, 0) - total - 1)
                    if cap <= 0 or grant < cap then cap = math.max(1, grant) end
                end
            end
        end
        local widest = cap > 0 and math.min(natural, cap) or natural
        widest = math.max(widest, math.min(L.titleMin, natural))
        for i = 1, count do
            local row = list:GetRow(i)
            if row then Layout(row, widest) end
        end
    end

    -- A click runs the saved search; inside the cooldown the rows only
    -- redraw, and the tooltip counts the wait down
    function panel:Select(item)
        if not GF.SearchAllowed() then
            self:Refresh()
            return
        end
        Tray:Run(item.entry)
    end

    function panel:Delete(index)
        if not index then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Saved.Remove(index)
    end

    -- The title and the line under it, then each section of the
    -- filter with every name, and the lines a row needs: a past season's
    -- dungeons, how the text gets into the box, the cooldown, a category
    -- the client no longer lists
    function panel:ShowTooltip(row, item)
        local d = item.describe
        local tooltip = GameTooltip
        tooltip:SetOwner(row, "ANCHOR_RIGHT", 25, 0)
        tooltip:ClearLines()
        tooltip:AddLine(d.title or "", 1, 1, 1, true)
        if d.sub then tooltip:AddLine(d.sub) end
        for _, section in ipairs(d.sections or {}) do
            tooltip:AddLine(" ")
            tooltip:AddLine(section.label)
            for _, line in ipairs(section.lines) do
                tooltip:AddLine(line, 1, 1, 1)
            end
        end
        local notes = {}
        if d.stale then
            notes[#notes + 1] = { "Includes dungeons from a past season, left out of the search", RED }
        end
        if d.text and d.text ~= "" then
            local mod = ModifierName()
            notes[#notes + 1] = { string.format("Click, then %s+C and %s+V to search for %s", mod, mod, d.text) }
        end
        if not GF.SearchAllowed() then
            notes[#notes + 1] = { string.format("Searching again in %d s", math.ceil(GF.SearchCooldownLeft())) }
        end
        if Tray.blockedKey and Tray.blockedKey == item.key then
            notes[#notes + 1] = { "This category is not available now", RED }
        end
        if #notes > 0 then tooltip:AddLine(" ") end
        for _, note in ipairs(notes) do
            local color = note[2]
            if color then
                tooltip:AddLine(note[1], color[1], color[2], color[3], true)
            else
                tooltip:AddLine(note[1], nil, nil, nil, true)
            end
        end
        tooltip:Show()
        if addon.Tooltip and addon.Tooltip.StyleDirect then addon.Tooltip.StyleDirect() end
    end

    -- The rows from the list, the one that matches the search as it stands
    -- selected while the search view is up, and the tray's height set from
    -- the count; inside the cooldown the rows redraw as it ends
    function panel:Refresh()
        -- A paste ends with the search view
        if Tray.paste and UI.view ~= "search" then Tray:EndPaste(true) end
        local entries = Saved.List()
        local sets = Saved.GroupSets()
        local items = {}
        for i, entry in ipairs(entries) do
            local describe = Saved.Describe(entry, sets)
            items[i] = { entry = entry, describe = describe, key = Saved.Key(entry), chunks = Chunks(describe.columns) }
        end
        self._items = items
        self._list:SetItems(items)
        -- Widths read from text set in this pass can be stale, so the rows
        -- are laid out again a frame on
        self:LayoutRows()
        C_Timer.After(0, function()
            if self._items == items and self:IsShown() then self:LayoutRows() end
        end)

        local index
        if UI.view == "search" then
            local live = Saved.Capture()
            local key = live and Saved.Key(live)
            for i, item in ipairs(items) do
                if item.key == key then
                    index = i
                    break
                end
            end
        end
        self._list:SetSelected(index)

        local rowsHeight = #items * L.rowHeight
        self._list.frame:SetHeight(math.max(1, rowsHeight))
        local height = 0
        if #items > 0 then
            height = L.boxTop + L.captionTop + L.captionHeight + L.captionGap + rowsHeight + L.boxPad + L.boxBottom
        end
        UI:SetTrayHeight(height)

        if not GF.SearchAllowed() then
            C_Timer.After(GF.SearchCooldownLeft() + 0.05, function()
                if self:IsShown() then self:Refresh() end
            end)
        end
    end

    function panel:Cleanup()
        Tray:EndPaste(true)
        if Tray.copyBox then
            Tray.copyBox._holder:Hide()
            Tray.copyBox = nil
        end
        self._list:Cleanup()
        if Tray.panel == self then Tray.panel = nil end
    end

    local function RefreshIfShown()
        if panel:IsShown() then panel:Refresh() end
    end

    -- A save or a delete shows or hides the tray; the rest redraws it
    GF.Listen("saved", function() UI:SyncTray() end)
    GF.Listen("searching", RefreshIfShown)
    GF.Listen("results", function(wasSearching)
        local paste = Tray.paste
        if wasSearching and paste and (paste.step == "searching" or paste.step == "enter") then
            if paste.step == "searching" then
                Saved.autoSearch = "ran"
                local blizzard = paste.sp and paste.sp.SearchBox
                if blizzard then pcall(blizzard.ClearFocus, blizzard) end
            end
            Tray:EndPaste(true)
        end
        RefreshIfShown()
    end)
    -- The box's text change notes the filter topic inside the key press, so
    -- the paste's search runs from it
    GF.Listen("filter", function()
        Tray:CheckPaste()
        RefreshIfShown()
    end)

    return panel
end

UI.trayBuilder = Build
