-- search.lua - the Search panel: the category's name, the filter list, the
-- hosted search box with its auto-complete, the refresh, the results, and
-- Back and Sign Up under them.
--
-- The search box is Blizzard's own, hosted in a Scoot holder, so its Enter
-- and its clear button run Blizzard's handlers and the C side reads its
-- text. Refresh runs Blizzard's DoSearch from its click; an auto-complete
-- row sets the box to that activity through the API and searches the same
-- way. The results are the component's copy, one row per id, each row read
-- afresh from the API on render as Blizzard's row is. The filter list
-- writes the client's advanced or language filter and redraws the rows;
-- it stands in a drawer out of the window's right edge, wide for the
-- Dungeons filter's columns and narrow for the language rows.
--
-- A search shows on the results pane as a sweep: the rows there dim under
-- a veil and a line scans them while the answer is on its way, and when it
-- lands the line runs once from the top with the new rows coming up behind
-- it. Sign Up and Refresh say why they are off in their tooltips.
local addonName, addon = ...

local GF = addon.GroupFinder
local UI = GF.UI
local LAYOUT = UI.LAYOUT
local Host = GF.Host
local Str = GF.Str
local SS = addon.SecretSafe

local function Controls()
    return addon.UI.Controls
end

local function Theme()
    return addon.UI.Theme
end

local function M()
    return addon.UI.Controls.Metrics()
end

local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }

-- The search box template's own art, put at alpha 0 while hosted; the
-- clear button keeps its handler and loses its textures
local SEARCH_ART = { "Left", "Middle", "Right", "searchIcon" }
local SEARCH_ART_FRAMES = { "clearButton" }

-- Where the search box goes back to when released, from Blizzard's XML
local function SearchBoxFallbackPoints()
    local sp = LFGListFrame and LFGListFrame.SearchPanel
    if not sp then return nil end
    return {
        { "TOPLEFT", sp.CategoryName, "BOTTOMLEFT", 4, -7 },
        { "RIGHT", sp.FilterButton, "LEFT", -42, 0 },
    }
end

local function SearchPanel()
    return LFGListFrame and LFGListFrame.SearchPanel
end

local function SelectedCategory()
    local cs = LFGListFrame and LFGListFrame.CategorySelection
    return cs and GF.plainNumber(cs.selectedCategory)
end

local function SetTextSafe(fs, value)
    if type(value) == "string" then
        fs:SetText(value)
    else
        fs:SetText("")
    end
end

-- A string that is plain and not empty; a kstring or a secret fails the
-- test inside pcall and reads as absent
local function NonEmpty(value)
    local ok, result = pcall(function() return type(value) == "string" and value ~= "" end)
    return ok and result == true
end

local function Timer(row)
    if not row._expiration then return end
    local left = math.max(0, row._expiration - GetTime())
    row._timer:SetText(string.format("%d:%.2d", math.floor(left / 60), math.floor(left % 60)))
end

--------------------------------------------------------------------------------
-- The rows
--------------------------------------------------------------------------------

local function PaintRow(row)
    local r, g, b, a = row._backdrop:LabelColor()
    if row._nameColor then
        row._name:SetTextColor(row._nameColor[1], row._nameColor[2], row._nameColor[3], row._nameColor[4] or 1)
    else
        row._name:SetTextColor(r, g, b, a or 1)
    end
end

-- The name's right edge stands a gap off the row's right column: the
-- roster's width for a group on the grid, the counts column for a larger
-- group, so a raid's longer name takes the room the grid leaves and a
-- long name ends short of the icons
local function SetNameColumn(row, column)
    local padX = (M().listRow or {}).padX or 8
    row._name:SetPoint("RIGHT", row, "RIGHT", -(padX + column + LAYOUT.search.columnGap), 0)
end

local function ClearRosters(row)
    row._roster:SetLines({})
    row._counts:SetLines({})
end

local function CreateRow(row)
    local C = Controls()
    local L = LAYOUT.search
    local padX = (M().listRow or {}).padX or 8

    row._name = UI.PrimaryText(row, "label")
    row._name:SetPoint("TOPLEFT", row, "TOPLEFT", padX, -L.nameTop)
    SetNameColumn(row, L.rightColumn)
    row._name:SetWordWrap(false)

    row._activity = UI.DimText(row, "desc", L.subSize)
    row._activity:SetPoint("TOPLEFT", row._name, "BOTTOMLEFT", L.subIndent, -1)
    row._activity:SetPoint("RIGHT", row._name, "RIGHT", 0, 0)
    row._activity:SetWordWrap(false)

    row._playstyle = UI.DimText(row, "desc", L.subSize)
    row._playstyle:SetPoint("TOPLEFT", row._activity, "BOTTOMLEFT", 0, -1)
    row._playstyle:SetPoint("RIGHT", row._name, "RIGHT", 0, 0)
    row._playstyle:SetWordWrap(false)
    local lr, lg, lb = Theme():GetDimTextLightColor()
    row._playstyle:SetTextColor(lr, lg, lb, 1)

    local R = L.roster
    row._roster = C.CreateRoster(row, {
        lines = R.lines, lineHeight = R.lineHeight, width = L.rightColumn, fontSize = R.fontSize,
        glyphWidth = R.glyphWidth, gap = R.gap, markWidth = R.markWidth, markHeight = R.markHeight,
        markY = R.markY, iconSize = R.iconSize, icons = UI.RoleIcons(), leaderMark = UI.LEADER_MARK,
    })
    row._roster:SetPoint("TOPRIGHT", row, "TOPRIGHT", -padX, -R.top)

    -- The counts grid for a group past the roster's lines, centred on the row
    local Cn = L.counts
    row._counts = C.CreateRoster(row, {
        lines = Cn.lines, lineHeight = Cn.lineHeight, width = Cn.width, fontSize = Cn.fontSize,
        glyphWidth = Cn.glyphWidth, gap = Cn.gap, iconSize = Cn.iconSize, icons = UI.RoleIcons(),
    })
    row._counts:SetPoint("RIGHT", row, "RIGHT", -padX, 0)

    row._voice = C.CreateTag(row, { text = "VOICE", tone = "dim" })
    row._voice:SetPoint("TOPLEFT", row._playstyle, "BOTTOMLEFT", 0, -2)
    row._voice:Hide()

    row._status = C.CreateTag(row, { text = "", tone = "accent" })
    row._status:Hide()

    row._timer = UI.DimText(row, "miniLabel")
    row._timer:SetJustifyH("RIGHT")
    row._timer:Hide()

    row._cancel = UI.MakeButton(row, "x", function()
        if row._resultID then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            C_LFGList.CancelApplication(row._resultID)
        end
    end, 22)
    row._cancel:SetHeight(22)
    row._cancel:Hide()
end

-- The right column by the activity's display type: a line per member for
-- a group the grid holds, in role order with the leader first in their
-- role and the crown and the rating on the leader's line, the open slots
-- blank; for a larger group the counts per role on the counts grid, which
-- stands larger and centred on the row in the lighter dim, since the
-- lines stand for many classes; n/m for a player count on that grid's
-- middle line. The members come one by one from the client, and when any
-- is missing its role the counts stand in on the roster, class colored
-- and named where the client gives the classes.
local function RenderRoster(row, id, info, counts, dimmed)
    local L = LAYOUT.search
    local R = L.roster
    local activity = GF.ActivityInfo(GF.ActivityID(info))
    row._roster:SetDimmed(dimmed)
    row._counts:SetDimmed(dimmed)
    if not activity or not counts then
        ClearRosters(row)
        SetNameColumn(row, L.rightColumn)
        return
    end
    local D = Enum.LFGListDisplayType
    local kind = activity.displayType
    local maxPlayers = GF.plainNumber(activity.maxNumPlayers)
    local lr, lg, lb = Theme():GetDimTextLightColor()
    local light = { lr, lg, lb }
    local entries = {}
    local onCounts = false
    local enumerate = D and (kind == D.RoleEnumerate or kind == D.ClassEnumerate)

    if enumerate and (maxPlayers or R.lines) <= R.lines then
        local max = maxPlayers or R.lines
        local members, complete = GF.Members(id, GF.plainNumber(info.numMembers) or 0)
        if complete then
            local byRole = { TANK = {}, HEALER = {}, DAMAGER = {} }
            local rest = {}
            for _, m in ipairs(members) do
                local bucket = byRole[m.role] or rest
                if m.leader then
                    table.insert(bucket, 1, m)
                else
                    bucket[#bucket + 1] = m
                end
            end
            -- The leader's line reads as the others, spec and class color;
            -- the name is in the tooltip
            local rating = GF.LeaderRating(info, activity)
            local function Add(m)
                local cr, cg, cb
                if m.class then cr, cg, cb = addon.GetClassColorRGB(m.class) end
                local text = m.spec or m.className
                entries[#entries + 1] = {
                    role = byRole[m.role] and m.role or nil, filled = true,
                    color = cr and { cr, cg, cb } or nil, text = text,
                    leader = m.leader, trailing = m.leader and rating or nil,
                }
            end
            for _, role in ipairs(ROLE_ORDER) do
                for _, m in ipairs(byRole[role]) do Add(m) end
            end
            for _, m in ipairs(rest) do Add(m) end
        else
            local names = LOCALIZED_CLASS_NAMES_MALE
            local byClass = type(counts.classesByRole) == "table"
            for _, role in ipairs(ROLE_ORDER) do
                local classes = byClass and counts.classesByRole[role]
                if type(classes) == "table" then
                    for class, num in pairs(classes) do
                        local cr, cg, cb = addon.GetClassColorRGB(class)
                        for _ = 1, (GF.plainNumber(num) or 0) do
                            entries[#entries + 1] = {
                                role = role, filled = true,
                                color = cr and { cr, cg, cb } or nil,
                                text = type(names) == "table" and names[class] or nil,
                            }
                        end
                    end
                else
                    for _ = 1, (GF.plainNumber(counts[role]) or 0) do
                        entries[#entries + 1] = { role = role, filled = true }
                    end
                end
            end
        end
        -- An open slot is a blank line
        while #entries > max do table.remove(entries) end
    elseif enumerate or (D and kind == D.RoleCount) then
        onCounts = true
        for _, role in ipairs(ROLE_ORDER) do
            entries[#entries + 1] = {
                role = role, filled = true, color = light,
                text = tostring(GF.plainNumber(counts[role]) or 0),
            }
        end
    elseif D and kind == D.PlayerCount then
        onCounts = true
        local total = (GF.plainNumber(counts.TANK) or 0) + (GF.plainNumber(counts.HEALER) or 0)
            + (GF.plainNumber(counts.DAMAGER) or 0) + (GF.plainNumber(counts.NOROLE) or 0)
        entries[2] = { filled = true, color = light, text = string.format("%d/%d", total, maxPlayers or total) }
    end

    if onCounts then
        row._roster:SetLines({})
        row._counts:SetLines(entries)
        SetNameColumn(row, L.counts.width)
    else
        row._counts:SetLines({})
        row._roster:SetLines(entries)
        SetNameColumn(row, L.rightColumn)
    end
end

local function RenderRow(panel, row, item)
    local theme = Theme()
    local padX = (M().listRow or {}).padX or 8
    local id = item.resultID
    row._resultID = id
    row._expiration = nil

    -- The fonts first: a string styled while empty keeps its creation font
    theme:ApplyFont(row._name, "label")
    theme:ApplyFont(row._activity, "desc", LAYOUT.search.subSize)
    theme:ApplyFont(row._playstyle, "desc", LAYOUT.search.subSize)
    theme:ApplyFont(row._timer, "miniLabel")

    local info = GF.ResultInfo(id)
    if not info then
        row._name:SetText("")
        row._activity:SetText("")
        row._playstyle:SetText("")
        ClearRosters(row)
        row._voice:Hide()
        row._status:Hide()
        row._timer:Hide()
        row._cancel:Hide()
        row._backdrop:SetStatus(nil)
        return
    end

    local _, appStatus, pendingStatus, appDuration = GF.Application(id)
    local isApplication = appStatus ~= "none" or pendingStatus ~= nil
    local isAppFinished = isApplication and GF.IsStatusInactive(appStatus)
    local guid = GF.plain(info.partyGUID)
    local isDeclined = GF.IsDeclined(appStatus) or (guid ~= nil and GF.state.declines[guid] ~= nil)
    local isDelisted = GF.plainBool(info.isDelisted) == true
    local friends = (GF.plainNumber(info.numBNetFriends) or 0) + (GF.plainNumber(info.numCharFriends) or 0)
        + (GF.plainNumber(info.numGuildMates) or 0)

    SetTextSafe(row._name, info.name)
    if isDeclined or isDelisted or isAppFinished then
        local dr, dg, db = theme:GetDimTextColor()
        row._nameColor = { dr, dg, db, 1 }
    elseif friends > 0 then
        local ar, ag, ab = theme:GetAccentColor()
        row._nameColor = { ar, ag, ab, 0.85 }
    else
        row._nameColor = nil
    end

    SetTextSafe(row._activity, GF.ActivityName(info))
    row._playstyle:SetText(GF.GeneralPlaystyleString(GF.plainNumber(info.generalPlaystyle)))

    local counts = GF.MemberCounts(id)
    local dimmed = isDelisted or isAppFinished

    -- The right column: the status, countdown and cancel of an application,
    -- else the composition
    local text, lit, pending = GF.StatusLine(appStatus, pendingStatus)
    local right = -padX
    if text then
        ClearRosters(row)
        SetNameColumn(row, LAYOUT.search.rightColumn)
        local showCancel = pendingStatus ~= "applied"
        row._cancel:SetShown(showCancel)
        if showCancel then
            row._cancel:SetEnabled((LFGListUtil_IsAppEmpowered and LFGListUtil_IsAppEmpowered()) and true or false)
            row._cancel:ClearAllPoints()
            row._cancel:SetPoint("RIGHT", row, "RIGHT", right, 0)
            right = right - 22 - 4
        end
        if pending and appDuration then
            row._expiration = GetTime() + appDuration
            Timer(row)
            row._timer:ClearAllPoints()
            row._timer:SetPoint("RIGHT", row, "RIGHT", right, 0)
            row._timer:Show()
            right = right - (row._timer:GetStringWidth() or 30) - 4
            panel:StartTicker()
        else
            row._timer:Hide()
        end
        row._status:SetTone(lit and "accent" or "dim")
        row._status:SetText(text)
        row._status:ClearAllPoints()
        row._status:SetPoint("RIGHT", row, "RIGHT", right, 0)
        row._status:Show()
    else
        row._status:Hide()
        row._timer:Hide()
        row._cancel:Hide()
        RenderRoster(row, id, info, counts, dimmed)
    end

    row._voice:SetShown(NonEmpty(info.voiceChat))

    local wash
    if isApplication and not isAppFinished then
        wash = "accent"
    elseif isDeclined then
        wash = "dim"
    end
    row._backdrop:SetStatus(wash)
    PaintRow(row)
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

local function Build(parent)
    local panel = UI.MakePanel(parent)
    local C = Controls()
    local L = LAYOUT.search
    local R = L.roster
    local boxX = LAYOUT.panel.boxX
    local pad = (M().collapsible or {}).contentPadding or 12

    -- The category's name, and the filter list's button at the row's right
    panel._heading = UI.MakeHeading(panel, "")
    panel._heading:SetPoint("RIGHT", panel, "RIGHT", -boxX, 0)
    panel._heading:SetWordWrap(false)

    panel._filter = UI.MakeButton(panel, Str("FILTER", "Filter"), function() panel:OpenFilter() end, L.filterWidth)
    panel._filter:SetHeight(L.rowHeight)
    panel._filter:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -boxX, -L.rowY)

    -- The heavy arrow: the mono face has no circle arrow and no magnifier,
    -- and the arrow reads as "go" beside a search box. Off for the cooldown
    -- after a search, which its tooltip counts down.
    panel._refresh = UI.MakeButton(panel, "\226\158\156", function() panel:Search() end, L.rowHeight, function()
        if not GF.SearchAllowed() then
            return string.format("Searching again in %d s", math.ceil(GF.SearchCooldownLeft()))
        end
        return Str("LFG_LIST_SEARCH_AGAIN", "Search again")
    end)
    panel._refresh:SetHeight(L.rowHeight)

    -- The hosted box's holder, and the x over Blizzard's clear button
    local holder = CreateFrame("Frame", nil, panel)
    Host.DressHolder(holder)
    holder:SetHeight(L.rowHeight)
    holder:SetPoint("TOPLEFT", panel, "TOPLEFT", boxX, -L.rowY)
    holder:SetPoint("RIGHT", panel._refresh, "LEFT", -L.gap, 0)
    panel._holder = holder
    panel._clear = UI.AccentText(holder, "label")
    panel._clear:SetText("x")
    panel._clear:SetAlpha(0.75)
    panel._clear:Hide()

    -- The results
    local box = UI.MakeBox(panel, L.boxTop)
    panel._box = box
    local list = C.CreateScrollList({
        parent = box,
        rowHeight = R.top + R.lines * R.lineHeight + R.bottom,
        createRow = CreateRow,
        render = function(row, item) RenderRow(panel, row, item) end,
        onSelect = function(item, index) panel:SelectResult(item.resultID, index) end,
        onRightClick = function(item) panel:OpenRowMenu(item.resultID) end,
        onEnter = function(item, _, row)
            panel:ShowTooltip(row, item.resultID)
            PaintRow(row)
        end,
        onLeave = function(_, _, row)
            GameTooltip:Hide()
            PaintRow(row)
        end,
    })
    list.frame:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -pad)
    list.frame:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -pad, pad)
    panel._list = list

    panel._empty = C.CreateEmptyState({ parent = box, text = "" })
    panel._empty:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -pad)
    panel._empty:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -pad, pad)
    panel._empty:Hide()

    -- Start a Group under the no-results message, as Blizzard's pane offers
    -- it; off for the reason its tooltip gives
    panel._start = UI.MakeButton(box, Str("START_A_GROUP", "Start a Group"), function() panel:StartGroup() end,
        LAYOUT.buttonWidth, function() return GF.StartGroupBlock() end)
    panel._start:SetPoint("TOP", panel._empty, "CENTER", 0, -L.startGroupY)
    panel._start:Hide()

    -- The redraw over the rows and the message alike
    panel._sweep = C.CreateSweep({ parent = box })
    panel._sweep:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -pad)
    panel._sweep:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -pad, pad)
    panel._sweep:SetFrameLevel(list.frame:GetFrameLevel() + 10)

    -- The bottom edge. Sign Up is off for the reason Blizzard's button
    -- gives, in its tooltip; an empty selection is left unsaid.
    panel._back = UI.MakeButton(panel, Str("BACK", "Back"), function() panel:Back() end, LAYOUT.buttonWidth)
    panel._back:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LAYOUT.panel.buttonX, LAYOUT.panel.buttonY)

    panel._signUp = UI.MakeButton(panel, Str("SIGN_UP", "Sign Up"), function() panel:SignUp() end,
        LAYOUT.buttonWidth, function() return GF.SignUpBlock(true) end)
    panel._signUp:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LAYOUT.panel.buttonX, LAYOUT.panel.buttonY)

    panel._leaver = C.CreateTag(panel, { text = "LEAVER", tone = "dim" })
    panel._leaver:SetPoint("RIGHT", panel._signUp, "LEFT", -6, 0)
    panel._leaver:Hide()

    -- The lists: the filter in its drawer, the auto-complete, the row
    -- menu. A list reads the labels before the keys, so every getter
    -- builds the whole set; it is a few dozen strings
    panel._filterMode = "languages"

    -- The filter's drawer out of the window's right edge, its list
    -- embedded and built as the drawer opens: the Dungeons filter in its
    -- sections across the wide drawer, the languages down the narrow one.
    -- The list names no width, so it measures the drawer's content at each
    -- open, after OpenFilter has sized the drawer for the mode
    panel._drawer = C.CreateDrawer({
        parent = UI:GetFrame(),
        width = L.filterDrawerWidth,
        onOpen = function(drawer)
            panel._dungeonsCleared = false
            drawer:SetContentHeight(panel._filterList:Open())
        end,
        onClose = function() panel._filterList:Close() end,
    })
    panel._filterList = C.CreatePopupList({
        embed = panel._drawer.content,
        multiSelect = true,
        fontSize = L.filterListFont,
        getKeys = function() return (panel:FilterItems()) end,
        getValues = function() return select(2, panel:FilterItems()) end,
        getSections = function() return select(3, panel:FilterItems()) end,
        isChecked = function(key) return panel:FilterChecked(key) end,
        isInert = function(key) return panel:FilterInert(key) end,
        onToggle = function(key, checked) panel:FilterToggle(key, checked) end,
    })

    panel._autoKeys, panel._autoLabels = {}, {}
    panel._auto = C.CreatePopupList({
        anchor = holder,
        silent = true,
        getKeys = function() return panel._autoKeys end,
        getValues = function() return panel._autoLabels end,
        getSelectedKey = function() return panel._autoSelected end,
        isInert = function(key) return key == "more" end,
        onSelect = function(key) panel:PickActivity(key) end,
    })

    panel._menu = C.CreatePopupList({
        width = 200,
        getKeys = function() return { "whisper", "report", "advertisement" } end,
        getValues = function()
            return {
                whisper = Str("WHISPER_LEADER", "Whisper leader"),
                report = Str("LFG_LIST_REPORT_GROUP_FOR", "Report group"),
                advertisement = Str("REPORT_GROUP_FINDER_ADVERTISEMENT", "Report advertisement"),
            }
        end,
        getSelectedKey = function() return nil end,
        isInert = function(key) return key == "whisper" and not panel._menuLeader end,
        onSelect = function(key) panel:MenuAction(key) end,
    })

    ----------------------------------------------------------------------------
    -- The box
    ----------------------------------------------------------------------------

    -- Blizzard's panel sizes its box on show, so it is hosted again on every
    -- show; the hooks go on once
    function panel:TakeBox()
        local sp = SearchPanel()
        local editBox = sp and sp.SearchBox
        if not editBox then return end
        local textInset = (M().field or {}).textInset or 8
        Host.Take("search", editBox, self._holder, {
            artKeys = SEARCH_ART,
            artFrames = SEARCH_ART_FRAMES,
            textInsets = { textInset, 22, 0, 0 },
            fallbackPoints = SearchBoxFallbackPoints(),
        })
        local clearButton = editBox.clearButton
        if clearButton then
            self._clear:ClearAllPoints()
            self._clear:SetPoint("CENTER", clearButton, "CENTER", 0, 0)
            self._clear:SetShown(clearButton:IsShown())
        end
        if self._boxHooked then return end
        self._boxHooked = true
        editBox:HookScript("OnTextChanged", function()
            if clearButton then self._clear:SetShown(clearButton:IsShown()) end
            self:RefreshAuto()
        end)
        if clearButton then
            -- The x comes up under the cursor, as the button's own icon would
            clearButton:HookScript("OnEnter", function() self._clear:SetAlpha(1) end)
            clearButton:HookScript("OnLeave", function() self._clear:SetAlpha(0.75) end)
        end
        editBox:HookScript("OnEditFocusGained", function() self:RefreshAuto() end)
        editBox:HookScript("OnEditFocusLost", function() self._auto:Close() end)
        editBox:HookScript("OnTabPressed", function() self:RefreshAuto() end)
        editBox:HookScript("OnArrowPressed", function() self:RefreshAuto() end)
    end

    -- The auto-complete, from the same call Blizzard's makes, with the row
    -- Blizzard's own Tab and arrows selected lit the same
    function panel:RefreshAuto()
        local sp = SearchPanel()
        local editBox = sp and sp.SearchBox
        if not (editBox and self:IsShown()) then return end
        local text = editBox:GetText()
        if type(text) ~= "string" or text == "" or not editBox:HasFocus() then
            self._auto:Close()
            return
        end
        local categoryID = GF.plainNumber(sp.categoryID)
        if not categoryID then self._auto:Close() return end
        local filters = GF.ResolveCategoryFilters(categoryID, GF.plainNumber(sp.filters) or 0)
        local ids = C_LFGList.GetAvailableActivities(categoryID, nil, filters, text)
        if type(ids) ~= "table" or #ids == 0 then
            self._auto:Close()
            return
        end
        if LFGListUtil_SortActivitiesByRelevancy then
            LFGListUtil_SortActivitiesByRelevancy(ids)
        end
        local keys, labels = {}, {}
        local shown = math.min(#ids, GF.MAX_AUTOCOMPLETE)
        for i = 1, shown do
            local id = ids[i]
            if i == shown and shown < #ids then
                keys[#keys + 1] = "more"
                labels.more = string.format(Str("LFG_LIST_AND_MORE", "and %d more"), #ids - shown + 1)
            else
                keys[#keys + 1] = id
                local ok, name = pcall(C_LFGList.GetActivityFullName, id)
                labels[id] = (ok and type(name) == "string") and name or tostring(id)
            end
        end
        self._autoKeys, self._autoLabels = keys, labels
        self._autoSelected = sp.AutoCompleteFrame and GF.plainNumber(sp.AutoCompleteFrame.selected) or nil
        self._auto:Open()
    end

    function panel:PickActivity(key)
        if key == "more" then return end
        local sp = SearchPanel()
        if not (sp and LFGListSearchPanel_DoSearch) then return end
        if not GF.SearchAllowed() then
            self:RefreshButtons()
            return
        end
        C_LFGList.SetSearchToActivity(key)
        LFGListSearchPanel_DoSearch(sp)
        if sp.SearchBox then sp.SearchBox:ClearFocus() end
    end

    ----------------------------------------------------------------------------
    -- Searching: Blizzard's DoSearch, which the host's hook notes
    ----------------------------------------------------------------------------

    function panel:Search()
        local sp = SearchPanel()
        if not (sp and LFGListSearchPanel_DoSearch) then return end
        if not GF.SearchAllowed() then
            self:RefreshButtons()
            return
        end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        LFGListSearchPanel_DoSearch(sp)
    end

    -- Back drops the rows, as Blizzard's Clear does, so the next Find Group
    -- starts from an empty pane and not another category's rows
    function panel:Back()
        if not (LFGListFrame and LFGListFrame_SetActivePanel) then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        GF.state.selectedResult = nil
        GF.state.results = {}
        self._list:SetItems({})
        self._sweep:Stop()
        self._drawer:Close(true)
        LFGListFrame_SetActivePanel(LFGListFrame, LFGListFrame.CategorySelection)
    end

    function panel:SignUp()
        local id = GF.state.selectedResult
        if not id or GF.SignUpBlock() then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        UI.SignUp:Show(id)
    end

    -- The listing form for this search's category, with the panel's
    -- preferred filters as its base, as Blizzard's own button passes them
    function panel:StartGroup()
        local sp = SearchPanel()
        if not (sp and UI.Create) or GF.StartGroupBlock() then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        UI.Create:Open(GF.plainNumber(sp.categoryID), GF.plainNumber(sp.filters) or 0, GF.plainNumber(sp.preferredFilters))
    end

    -- A click selects a result that can take an application; any other
    -- click leaves the selection where it was
    function panel:SelectResult(id, index)
        if GF.CanSelect(id) then
            GF.state.selectedResult = id
            self._selectedIndex = index
        else
            self._list:SetSelected(self._selectedIndex)
        end
        self:PaintRows()
        self:RefreshButtons()
    end

    function panel:PaintRows()
        for i = 1, #self._list._items do
            local row = self._list:GetRow(i)
            if row then PaintRow(row) end
        end
    end

    ----------------------------------------------------------------------------
    -- The filter list
    ----------------------------------------------------------------------------

    -- The advanced filter in three sections, as the owner laid them out:
    -- the role rows, the dungeons, then the difficulties beside the
    -- playstyles. The keys are the AdvancedFilterOptions fields, and a
    -- dungeon row's key carries the dungeon's group id, since the filter's
    -- activities list holds group ids despite its name.
    local ROLES = {
        { key = "needsTank", label = "LFG_LIST_NEEDS_TANK", role = 1 },
        { key = "needsHealer", label = "LFG_LIST_NEEDS_HEALER", role = 2 },
        { key = "needsDamage", label = "LFG_LIST_NEEDS_DAMAGE", role = 3 },
        { key = "needsMyClass", label = "LFG_LIST_CLASS_AVAILABLE", class = true },
        { key = "hasTank", label = "LFG_LIST_HAS_TANK" },
        { key = "hasHealer", label = "LFG_LIST_HAS_HEALER" },
    }
    local DIFFICULTY = { "difficultyNormal", "difficultyHeroic", "difficultyMythic", "difficultyMythicPlus" }
    local PLAYSTYLE = { "generalPlaystyle1", "generalPlaystyle2", "generalPlaystyle3", "generalPlaystyle4" }
    local LABELS = {
        difficultyNormal = "PLAYER_DIFFICULTY1", difficultyHeroic = "PLAYER_DIFFICULTY2",
        difficultyMythic = "PLAYER_DIFFICULTY6", difficultyMythicPlus = "PLAYER_DIFFICULTY_MYTHIC_PLUS",
        generalPlaystyle1 = "GROUP_FINDER_GENERAL_PLAYSTYLE1", generalPlaystyle2 = "GROUP_FINDER_GENERAL_PLAYSTYLE2",
        generalPlaystyle3 = "GROUP_FINDER_GENERAL_PLAYSTYLE3", generalPlaystyle4 = "GROUP_FINDER_GENERAL_PLAYSTYLE4",
    }
    -- A key's family: no difficulty checked reads as every difficulty
    -- checked, and the same for the playstyles, as Blizzard's menu reads it
    local FAMILY = {}
    for _, key in ipairs(DIFFICULTY) do FAMILY[key] = DIFFICULTY end
    for _, key in ipairs(PLAYSTYLE) do FAMILY[key] = PLAYSTYLE end
    local GROUP_PREFIX = "group:"

    local function AtMaxLevel()
        return GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel and GameRulesUtil.IsPlayerAtEffectiveMaxLevel()
    end

    local function CanChangeLanguages()
        return LFGListCanChangeLanguages and LFGListCanChangeLanguages() or false
    end

    -- The dungeons the filter lists, as Blizzard's menu lists them: this
    -- season's, the expansion's others, and the Timerunning set when the
    -- character is one; three lists of group ids, and all of them in one
    local function DungeonGroups()
        local F = Enum and Enum.LFGListFilter
        local season, expansion, timerunning = {}, {}, {}
        if not (F and C_LFGList.GetAvailableActivityGroups) then
            return season, expansion, timerunning, {}
        end
        local function fill(into, filters)
            local groups = C_LFGList.GetAvailableActivityGroups(GF.DUNGEONS_CATEGORY, filters)
            for _, id in ipairs(type(groups) == "table" and groups or {}) do into[#into + 1] = id end
        end
        local pve = F.PvE or 0
        fill(season, bit.bor(F.CurrentSeason or 0, pve))
        fill(expansion, bit.bor(F.CurrentExpansion or 0, F.NotCurrentSeason or 0, pve))
        if F.Timerunning and PlayerIsTimerunning and PlayerIsTimerunning() then
            fill(timerunning, bit.bor(F.Timerunning, pve))
        end
        local all = {}
        for _, part in ipairs({ season, expansion, timerunning }) do
            for _, id in ipairs(part) do all[#all + 1] = id end
        end
        return season, expansion, timerunning, all
    end

    local function IsGroupKey(key)
        return string.sub(key, 1, #GROUP_PREFIX) == GROUP_PREFIX
    end

    local function GroupID(key)
        return tonumber(string.sub(key, #GROUP_PREFIX + 1))
    end

    -- The filter's dungeon set and its size; an empty set reads as every
    -- dungeon checked
    local function GroupSet(enabled)
        local set, n = {}, 0
        for _, id in ipairs(type(enabled.activities) == "table" and enabled.activities or {}) do
            set[id] = true
            n = n + 1
        end
        return set, n
    end

    local function NoneOf(enabled, keys)
        for _, k in ipairs(keys) do
            if enabled[k] then return false end
        end
        return true
    end

    -- Dungeons at max level take the advanced filter; every other category
    -- the languages, as Blizzard's button decides. Returns the keys in
    -- order, the label per key, and the sections of the advanced filter.
    function panel:FilterItems()
        local keys, labels = {}, {}
        if SelectedCategory() == GF.DUNGEONS_CATEGORY and AtMaxLevel() then
            self._filterMode = "advanced"
            local sections = {}
            local function Section(label, columnLabels)
                local s = { label = label, labels = columnLabels, columns = 2, keys = {} }
                sections[#sections + 1] = s
                return s
            end
            local function Put(s, key, label)
                keys[#keys + 1] = key
                labels[key] = label
                s.keys[#s.keys + 1] = key
            end

            local roles = Section(Str("LFG_LIST_REQUIRE", "Roles"))
            local tank, healer, dps = C_LFGList.GetAvailableRoles()
            local avail = { tank, healer, dps }
            for _, entry in ipairs(ROLES) do
                if not entry.role or avail[entry.role] then
                    local label = Str(entry.label, entry.key)
                    if entry.class and PlayerUtil and PlayerUtil.GetClassName then
                        label = string.format(label, PlayerUtil.GetClassName())
                    end
                    Put(roles, entry.key, label)
                end
            end

            -- The dungeons: the two buttons, this season's in two columns,
            -- then the expansion's others and any Timerunning set, each a
            -- block of its own after a line of space
            local season, expansion, timerunning = DungeonGroups()
            local dungeons = Section(Str("DUNGEONS", "Dungeons"))
            dungeons.buttons = {
                { label = Str("CHECK_ALL", "Select all"), onClick = function() panel:SetAllDungeons(true) end },
                { label = Str("UNCHECK_ALL", "Unselect all"), onClick = function() panel:SetAllDungeons(false) end },
            }
            local function PutGroups(s, ids)
                for _, id in ipairs(ids) do
                    local ok, name = pcall(C_LFGList.GetActivityGroupInfo, id)
                    if ok and type(name) == "string" and name ~= "" then
                        Put(s, GROUP_PREFIX .. id, name)
                    end
                end
            end
            PutGroups(dungeons, season)
            for _, more in ipairs({ expansion, timerunning }) do
                if #more > 0 then
                    local block = Section(nil)
                    block.separator = "space"
                    PutGroups(block, more)
                end
            end

            local styles = Section(nil, {
                Str("LFG_LIST_DIFFICULTY", "Difficulty"),
                Str("GROUP_FINDER_FILTER_PLAYSTYLE", "Playstyle"),
            })
            for _, key in ipairs(DIFFICULTY) do Put(styles, key, Str(LABELS[key], key)) end
            for _, key in ipairs(PLAYSTYLE) do Put(styles, key, Str(LABELS[key], key)) end
            return keys, labels, sections
        end
        self._filterMode = "languages"
        local languages = C_LFGList.GetAvailableLanguageSearchFilter and C_LFGList.GetAvailableLanguageSearchFilter() or {}
        for _, lang in ipairs(languages) do
            keys[#keys + 1] = lang
            labels[lang] = Str("LFG_LIST_LANGUAGE_" .. string.upper(lang), lang)
        end
        return keys, labels, nil
    end

    function panel:FilterChecked(key)
        if self._filterMode == "advanced" then
            local enabled = C_LFGList.GetAdvancedFilter()
            if type(enabled) ~= "table" then return false end
            if IsGroupKey(key) then
                local set, n = GroupSet(enabled)
                -- An empty list reads as all checked, except right after
                -- Unselect all, when it reads as the player left it
                if n == 0 then return not self._dungeonsCleared end
                return set[GroupID(key)] == true
            end
            local family = FAMILY[key]
            if family and NoneOf(enabled, family) then return true end
            return enabled[key] == true
        end
        local enabled = C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter() or {}
        return enabled[key] == true
    end

    -- A default language stays on, as Blizzard's list has it
    function panel:FilterInert(key)
        if self._filterMode == "advanced" then return false end
        local defaults = C_LFGList.GetDefaultLanguageSearchFilter and C_LFGList.GetDefaultLanguageSearchFilter() or {}
        return defaults[key] == true
    end

    -- A toggle on a family that reads as all checked first writes the
    -- family on, so the one row comes off alone, as Blizzard's menu does
    function panel:FilterToggle(key, checked)
        if self._filterMode == "advanced" then
            local enabled = C_LFGList.GetAdvancedFilter()
            if type(enabled) ~= "table" then return end
            if IsGroupKey(key) then
                local _, _, _, ids = DungeonGroups()
                local set, n = GroupSet(enabled)
                if n == 0 and not self._dungeonsCleared then
                    for _, id in ipairs(ids) do set[id] = true end
                end
                set[GroupID(key)] = checked or nil
                local kept = {}
                for _, id in ipairs(ids) do
                    if set[id] then kept[#kept + 1] = id end
                end
                enabled.activities = kept
                self._dungeonsCleared = #kept == 0
            else
                local family = FAMILY[key]
                if family and NoneOf(enabled, family) then
                    for _, k in ipairs(family) do enabled[k] = true end
                end
                enabled[key] = checked and true or false
            end
            C_LFGList.SaveAdvancedFilter(enabled)
            self._list:Refresh()
            return
        end
        if not C_LFGList.SaveLanguageSearchFilter then return end
        local enabled = C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter() or {}
        enabled[key] = checked and true or false
        C_LFGList.SaveLanguageSearchFilter(enabled)
    end

    -- Select all writes every dungeon; Unselect all writes none, which the
    -- search reads as no dungeon filter, and the rows show it as the
    -- player left it until a dungeon is checked or the drawer opens again
    function panel:SetAllDungeons(on)
        local enabled = C_LFGList.GetAdvancedFilter()
        if type(enabled) ~= "table" then return end
        local _, _, _, ids = DungeonGroups()
        enabled.activities = on and ids or {}
        self._dungeonsCleared = not on
        C_LFGList.SaveAdvancedFilter(enabled)
        self._list:Refresh()
        self._filterList:Refresh()
    end

    -- The mode is settled by the items, so they are read first, and the
    -- drawer takes the mode's width before it comes out
    function panel:OpenFilter()
        self:FilterItems()
        self._drawer:Resize(self._filterMode == "advanced" and L.filterDrawerWidth or L.languageDrawerWidth)
        self._drawer:Toggle()
    end

    ----------------------------------------------------------------------------
    -- The row's menu and tooltip
    ----------------------------------------------------------------------------

    function panel:OpenRowMenu(id)
        local info = GF.ResultInfo(id)
        if not info then return end
        self._menuResult = id
        self._menuLeader = SS.plainString(info.leaderName)
        self._menu:OpenAtCursor()
    end

    function panel:MenuAction(key)
        local id = self._menuResult
        if not id then return end
        if key == "whisper" then
            if self._menuLeader and ChatFrameUtil and ChatFrameUtil.SendTell then
                ChatFrameUtil.SendTell(self._menuLeader)
            end
        elseif key == "report" then
            if LFGList_ReportListing then LFGList_ReportListing(id, self._menuLeader) end
        elseif key == "advertisement" then
            if LFGList_ReportAdvertisement then LFGList_ReportAdvertisement(id) end
        end
    end

    function panel:ShowTooltip(row, id)
        local info = GF.ResultInfo(id)
        if not info then return end
        local theme = Theme()
        local dr, dg, db = theme:GetDimTextColor()
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT", 25, 0)
        GameTooltip:ClearLines()
        pcall(function()
            if type(info.name) == "string" then GameTooltip:AddLine(info.name) end
            local activity = GF.ActivityName(info)
            if activity then GameTooltip:AddLine(activity, dr, dg, db) end
            if NonEmpty(info.comment) then GameTooltip:AddLine(info.comment, 1, 1, 1, true) end
            local ilvl = GF.plainNumber(info.requiredItemLevel) or 0
            if ilvl > 0 then
                GameTooltip:AddLine(string.format(Str("LFG_LIST_TOOLTIP_ILVL", "Item level %d+"), ilvl))
            end
            if NonEmpty(info.voiceChat) then
                GameTooltip:AddLine(string.format(Str("LFG_LIST_TOOLTIP_VOICE_CHAT", "Voice: %s"), info.voiceChat), nil, nil, nil, true)
            end
            -- The leader by name, spec and class in the class color, with the
            -- rating: the spec the row's leader line stands in for
            local leader = SS.plainString(info.leaderName)
            if leader then
                local lr, lg, lb = 1, 1, 1
                local members = GF.Members(id, GF.plainNumber(info.numMembers) or 0)
                for _, m in ipairs(members) do
                    if m.leader then
                        local who = (m.spec and m.className and (m.spec .. " " .. m.className)) or m.className
                        if who then leader = leader .. ", " .. who end
                        local cr, cg, cb
                        if m.class then cr, cg, cb = addon.GetClassColorRGB(m.class) end
                        if cr then lr, lg, lb = cr, cg, cb end
                        break
                    end
                end
                local rating = GF.LeaderRating(info, GF.ActivityInfo(GF.ActivityID(info)))
                if rating then leader = leader .. "  " .. rating end
                GameTooltip:AddLine(leader, lr, lg, lb)
            end
            local counts = GF.MemberCounts(id)
            if counts then
                GameTooltip:AddLine(string.format("%d T  %d H  %d D", GF.plainNumber(counts.TANK) or 0,
                    GF.plainNumber(counts.HEALER) or 0, GF.plainNumber(counts.DAMAGER) or 0), dr, dg, db)
            end
            local age = GF.plainNumber(info.age)
            if age and SecondsToTime then
                GameTooltip:AddLine(string.format(Str("LFG_LIST_TOOLTIP_AGE", "Age: %s"), SecondsToTime(age)), dr, dg, db)
            end
        end)
        GameTooltip:Show()
    end

    ----------------------------------------------------------------------------
    -- The countdown on applied rows
    ----------------------------------------------------------------------------

    function panel:StartTicker()
        if self._ticker then return end
        self._ticker = C_Timer.NewTicker(1, function() self:Tick() end)
    end

    function panel:StopTicker()
        if self._ticker then
            self._ticker:Cancel()
            self._ticker = nil
        end
    end

    function panel:Tick()
        local any = false
        if self:IsShown() then
            for i = 1, #self._list._items do
                local row = self._list:GetRow(i)
                if row and row:IsShown() and row._expiration then
                    Timer(row)
                    any = true
                end
            end
        end
        if not any then self:StopTicker() end
    end

    ----------------------------------------------------------------------------
    -- Refresh
    ----------------------------------------------------------------------------

    function panel:RefreshHeading()
        local sp = SearchPanel()
        local categoryID = sp and GF.plainNumber(sp.categoryID)
        local info = categoryID and C_LFGList.GetLfgCategoryInfo(categoryID)
        local name = type(info) == "table" and type(info.name) == "string" and info.name or ""
        if name ~= "" and LFGListUtil_GetDecoratedCategoryName then
            name = LFGListUtil_GetDecoratedCategoryName(name, GF.plainNumber(sp.filters) or 0, false)
        end
        self._heading:SetText(name)
    end

    -- The filter button shows when there is a filter to set, and the refresh
    -- sits against whichever is the row's right end
    function panel:RefreshLayout()
        local showFilter = CanChangeLanguages() or AtMaxLevel()
        self._filter:SetShown(showFilter)
        self._refresh:ClearAllPoints()
        if showFilter then
            self._refresh:SetPoint("RIGHT", self._filter, "LEFT", -L.gap, 0)
        else
            self._refresh:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -boxX, -L.rowY)
        end
    end

    -- While a search is out the rows on the pane stay as they are, dimmed
    -- under the sweep, and an empty pane says it is searching; the ids of
    -- the last answer are not re-read, since the client has let them go
    function panel:RefreshList()
        local state = GF.state
        self._start:Hide()
        if state.searching then
            if not (self._list.frame:IsShown() and #self._list._items > 0) then
                self._empty:SetBusy(true, Str("SEARCHING", "Searching"))
                self._empty:Show()
                self._list.frame:Hide()
            end
            self._sweep:Scan()
            return
        end

        local items = {}
        for i, id in ipairs(state.results) do items[i] = { resultID = id } end
        self._list:SetItems(items)
        local index
        if state.selectedResult then
            for i, item in ipairs(items) do
                if item.resultID == state.selectedResult then index = i break end
            end
            if not (index and GF.CanSelect(state.selectedResult)) then
                state.selectedResult = nil
                index = nil
            end
        end
        self._selectedIndex = index
        self._list:SetSelected(index)
        self:PaintRows()

        if state.searchFailed then
            local text = Str("LFG_LIST_SEARCH_FAILED", "Search failed")
            if state.failReason then text = text .. " (" .. tostring(state.failReason) .. ")" end
            self._empty:SetBusy(false, text)
            self._empty:Show()
            self._list.frame:Hide()
        elseif #items == 0 then
            self._empty:SetBusy(false, Str("LFG_LIST_NO_RESULTS_FOUND", "No groups found"))
            self._empty:Show()
            self._list.frame:Hide()
            self._start:SetEnabled(GF.StartGroupBlock() == nil)
            self._start:Show()
        else
            self._empty:SetBusy(false)
            self._empty:Hide()
            self._list.frame:Show()
        end
    end

    function panel:RefreshRow(id)
        for i, item in ipairs(self._list._items) do
            if item.resultID == id then
                local row = self._list:GetRow(i)
                if row and row:IsShown() then RenderRow(self, row, item) end
                return
            end
        end
    end

    function panel:RefreshButtons()
        self._signUp:SetEnabled(GF.SignUpBlock() == nil)
        self._start:SetEnabled(GF.StartGroupBlock() == nil)
        local allowed = GF.SearchAllowed()
        self._refresh:SetEnabled(allowed)
        if not allowed then
            C_Timer.After(GF.SearchCooldownLeft() + 0.05, function()
                if self:IsShown() then self:RefreshButtons() end
            end)
        end
        local selected = GF.state.selectedResult
        self._leaver:SetShown(selected ~= nil and GF.IsLeaverFlagged(selected))
    end

    function panel:Refresh()
        self:RefreshHeading()
        self:RefreshLayout()
        self:TakeBox()
        self:RefreshList()
        self:RefreshButtons()
    end

    function panel:Cleanup()
        self:StopTicker()
        self._list:Cleanup()
        self._filterList:Destroy()
        self._drawer:Cleanup()
        self._auto:Destroy()
        self._menu:Destroy()
    end

    panel:HookScript("OnHide", function()
        panel._auto:Close()
        panel._drawer:Close(true)
        panel._menu:Close()
        panel:StopTicker()
        panel._sweep:Stop()
    end)

    GF.Listen("searching", function()
        if panel:IsShown() then
            panel:RefreshList()
            panel:RefreshButtons()
        end
    end)
    -- The answer to a search comes up under the reveal pass; an update the
    -- client sends on its own is drawn in place
    GF.Listen("results", function(wasSearching)
        if panel:IsShown() then
            panel:RefreshList()
            panel:RefreshButtons()
            if wasSearching then panel._sweep:Reveal() end
        end
    end)
    GF.Listen("failed", function()
        if panel:IsShown() then
            panel:RefreshList()
            panel:RefreshButtons()
            panel._sweep:Reveal()
        end
    end)
    GF.Listen("result", function(id)
        if panel:IsShown() then
            panel:RefreshRow(id)
            panel:RefreshButtons()
        end
    end)
    GF.Listen("status", function(id)
        if panel:IsShown() then
            panel:RefreshRow(id)
            panel:RefreshButtons()
        end
    end)
    GF.Listen("buttons", function()
        if panel:IsShown() then panel:RefreshButtons() end
    end)
    GF.Listen("lockdown", function()
        if panel:IsShown() then panel:RefreshList() end
    end)

    return panel
end

UI.panelBuilders.search = Build
