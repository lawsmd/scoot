-- search.lua - the Search panel: the category's name, the filter list, the
-- hosted search box with its auto-complete, the refresh, the results with
-- a sign-up button on each row and the role column at their right
-- (roles.lua), and Back and Save Search under them (the saved searches'
-- tray and the save itself are saved.lua).
--
-- The search box is Blizzard's own, hosted in a Scoot holder, so its Enter
-- and its clear button run Blizzard's handlers and the C side reads its
-- text. The way in (UI.Search:Open) is Blizzard's StartFindGroup without
-- its panel switch: Blizzard's search panel is shown so its box renders
-- and never made the active panel, so its own row handlers never run on
-- the window's searches. Refresh runs Blizzard's DoSearch from its click;
-- an auto-complete row runs Blizzard's own fill, which puts the activity's
-- full name in the box, and the search from the same click when the
-- cooldown allows it, so text typed after the name narrows the search as
-- it does in Blizzard's own box. The results are the component's copy, one row
-- per id, each row read afresh from the API on render as Blizzard's row
-- is. The filter list writes the client's advanced or language filter and
-- redraws the rows; it stands in a drawer out of the window's right edge,
-- wide for the Dungeons filter's columns and narrow for the language rows.
--
-- A search shows on the results pane as a sweep: the rows there dim under
-- a veil and a line scans them while the answer is on its way, and when it
-- lands the line runs once from the top with the new rows coming up behind
-- it. A row's + applies to that group from its click, with the roles and
-- the note the column holds; it and Refresh say why they are off in their
-- tooltips.
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

-- The one color the palette does not name: the red Blizzard's row goes
-- under a group that no longer satisfies the filter, as the wash under
-- the row and the delisted line in the tooltip
local RED = { 0.85, 0.2, 0.2 }
local OFF_FILTER_WASH = { RED[1], RED[2], RED[3], 0.18 }

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

-- The tooltip's role icons, a local table in Blizzard's file
local ROLE_ATLASES_BORDERLESS = {
    TANK = "groupfinder-icon-role-micro-tank",
    HEALER = "groupfinder-icon-role-micro-heal",
    DAMAGER = "groupfinder-icon-role-micro-dps",
}

-- A best run as Blizzard's tooltip writes it: a plus per level of the
-- upgrade, the level in white, the dungeon in its score's rarity color.
-- MakeRunLevelWithIncrement is a local in Blizzard's file
local function RunLevelText(run)
    local pluses = ""
    for _ = 1, GF.plainNumber(run.bestLevelIncrement) or 0 do
        pluses = pluses .. Str("GROUPFINDER_PLUS", "+")
    end
    local level = HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(run.bestRunLevel)
    local color = C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor(run.bestRunLevel) or HIGHLIGHT_FONT_COLOR
    return pluses .. level .. " " .. color:WrapTextInColorCode(run.mapName)
end

--------------------------------------------------------------------------------
-- The way in: the search view over Blizzard's search panel
--------------------------------------------------------------------------------

local Search = {}
UI.Search = Search

-- Blizzard's StartFindGroup without its panel switch: the last results
-- cleared, the category set, the panel shown for its box, the view up,
-- and the one search, which the host's hook notes. The search panel's own
-- show builds rows only from results, and there are none after the clear.
-- beforeSearch(sp), optional, runs between the category and the search,
-- where a saved search fills the box (saved.lua); false from it leaves the
-- search unrun, for the player's Enter.
function Search:Open(categoryID, filters, baseFilters, beforeSearch)
    local lf, sp = LFGListFrame, SearchPanel()
    if not (lf and sp and categoryID) then return false end
    if not (LFGListSearchPanel_Clear and LFGListSearchPanel_SetCategory and LFGListSearchPanel_DoSearch) then
        return false
    end
    if not GF.SearchAllowed() then return false end
    LFGListSearchPanel_Clear(sp)
    -- SetCategory writes the box's own prompt, so a ghost from the last
    -- saved search is gone with it
    LFGListSearchPanel_SetCategory(sp, categoryID, filters or 0, baseFilters or GF.plainNumber(lf.baseFilters) or 0)
    Search.ghost = false
    sp:Show()
    UI:SetView("search")
    if beforeSearch and beforeSearch(sp) == false then return true end
    LFGListSearchPanel_DoSearch(sp)
    return true
end

-- The panel out of sight again, unless Blizzard has it active, and its box
-- back in it either way, since a panel Blizzard keeps up would show the
-- box in the window's holder on the next view; the caller syncs the window
function Search:Close()
    local lf, sp = LFGListFrame, SearchPanel()
    if sp and Search.ghost then Search.RestorePrompt(sp) end
    if sp and lf and SS.plainFrame(lf.activePanel) ~= sp then sp:Hide() end
    Host.Release("search")
    if UI.view == "search" then UI.view = nil end
end

-- A saved search's text as the box's prompt while the box is empty, where
-- the box would not take the text itself: Blizzard shows the prompt only
-- while the text is empty, so it stands until the player types
function Search.SetGhost(sp, text)
    local instructions = sp and sp.SearchBox and sp.SearchBox.Instructions
    if not instructions then return end
    instructions:SetText(text or "")
    Search.ghost = true
end

-- The category's own prompt back, as SetCategory writes it, since the host
-- gives the box back with its text and prompt as they stand
function Search.RestorePrompt(sp)
    Search.ghost = false
    local instructions = sp and sp.SearchBox and sp.SearchBox.Instructions
    if not instructions then return end
    local categoryID = GF.plainNumber(sp.categoryID)
    local info = categoryID and C_LFGList.GetLfgCategoryInfo(categoryID)
    local prompt = type(info) == "table" and type(info.searchPromptOverride) == "string"
        and info.searchPromptOverride or Str("FILTER", "Filter")
    instructions:SetText(prompt)
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
-- long name ends short of the icons; the sign-up button's column lies
-- past either
local function SetNameColumn(row, column)
    local L = LAYOUT.search
    local padX = (M().listRow or {}).padX or 8
    row._name:SetPoint("RIGHT", row, "RIGHT", -(padX + column + L.quickColumn + L.columnGap), 0)
end

local function ClearRosters(row)
    row._roster:SetLines({})
    row._counts:SetLines({})
end

-- The row's sign-up button: hidden for a delisted group and under an
-- application's status, else on when Blizzard's chain allows an
-- application, a role is chosen and the group has not declined the
-- player; the tooltip names the reason, or Sign Up, with the deserter
-- line for a Mythic+ group while the player is flagged
local function SetQuick(row)
    if row._quickHidden then
        row._quick:Hide()
        return
    end
    row._quick:SetEnabled(not row._declined and GF.SignUpBlock() == nil and UI.Roles:HasRole())
    row._quick:Show()
end

local function QuickTip(row)
    local text
    if row._declined then
        text = Str("LFG_LIST_APP_DECLINED", "Declined")
    else
        text = GF.SignUpBlock() or UI.Roles:Block() or Str("SIGN_UP", "Sign Up")
    end
    if row._resultID and GF.IsLeaverFlagged(row._resultID) then
        text = text .. "\n" .. Str("MYTHIC_PLUS_DESERTER_FLAGGED_SHORT", "You are flagged as a leaver")
    end
    return text
end

local function CreateRow(panel, row)
    local C = Controls()
    local L = LAYOUT.search
    local padX = (M().listRow or {}).padX or 8
    local columnRight = padX + L.quickColumn

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
    row._roster:SetPoint("TOPRIGHT", row, "TOPRIGHT", -columnRight, -R.top)

    -- The counts grid for a group past the roster's lines, centred on the row
    local Cn = L.counts
    row._counts = C.CreateRoster(row, {
        lines = Cn.lines, lineHeight = Cn.lineHeight, width = Cn.width, fontSize = Cn.fontSize,
        glyphWidth = Cn.glyphWidth, gap = Cn.gap, iconSize = Cn.iconSize, icons = UI.RoleIcons(),
    })
    row._counts:SetPoint("RIGHT", row, "RIGHT", -columnRight, 0)

    -- The sign-up button past the grid, centred on the row's right end
    local A = L.action
    row._quick = C:CreateButton({
        parent = row, text = "+", width = A.size, height = A.size, fontSize = A.font,
        borderWidth = A.border, borderAlpha = A.borderAlpha, labelAlpha = A.labelAlpha,
        onClick = function() panel:Apply(row._resultID) end,
        tooltip = function() return QuickTip(row) end,
    })
    row._quick:SetPoint("RIGHT", row, "RIGHT", -padX, 0)
    row._quick:Hide()

    row._voice = C.CreateTag(row, { text = "VOICE", tone = "dim" })
    row._voice:SetPoint("TOPLEFT", row._playstyle, "BOTTOMLEFT", 0, -2)
    row._voice:Hide()

    -- An application's word, and the countdown centred under it
    row._status = UI.DimText(row, "miniLabel")
    row._status:Hide()

    row._timer = UI.DimText(row, "miniLabel")
    row._timer:Hide()

    row._cancel = C:CreateButton({
        parent = row, text = "x", width = A.size, height = A.size, fontSize = A.font,
        borderWidth = A.border, borderAlpha = A.borderAlpha, labelAlpha = A.labelAlpha,
        onClick = function()
            if row._resultID then
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                C_LFGList.CancelApplication(row._resultID)
            end
        end,
    })
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
    theme:ApplyFont(row._status, "miniLabel")
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
        row._quickHidden = true
        row._quick:Hide()
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

    -- A delisted group or a finished application grays the whole row, as
    -- Blizzard's does; a declined one dims the name alone
    local dimmed = isDelisted or isAppFinished
    local stale = dimmed and LAYOUT.search.staleAlpha or 1
    SetTextSafe(row._name, info.name)
    if isDeclined or dimmed then
        local dr, dg, db = theme:GetDimTextColor()
        row._nameColor = { dr, dg, db, stale }
    elseif friends > 0 then
        local ar, ag, ab = theme:GetAccentColor()
        row._nameColor = { ar, ag, ab, 0.85 }
    else
        row._nameColor = nil
    end

    SetTextSafe(row._activity, GF.ActivityName(info))
    row._playstyle:SetText(GF.GeneralPlaystyleString(GF.plainNumber(info.generalPlaystyle)))
    row._activity:SetAlpha(stale)
    row._playstyle:SetAlpha(stale)
    row._voice:SetAlpha(stale)

    local counts = GF.MemberCounts(id)
    -- Off the filter while sitting on the pane, as Blizzard's row reads it
    -- on each update; the Dungeons category alone carries the filter
    local offFilter = SelectedCategory() == GF.DUNGEONS_CATEGORY and not GF.MatchesFilter(info, counts)

    -- The right column: the status, countdown and cancel of an application,
    -- else the composition with the sign-up button past it
    local text, lit, pending = GF.StatusLine(appStatus, pendingStatus)
    local right = -padX
    row._declined = isDeclined
    if text then
        ClearRosters(row)
        SetNameColumn(row, LAYOUT.search.rightColumn)
        row._quickHidden = true
        row._quick:Hide()
        local showCancel = pendingStatus ~= "applied"
        row._cancel:SetShown(showCancel)
        if showCancel then
            row._cancel:SetEnabled((LFGListUtil_IsAppEmpowered and LFGListUtil_IsAppEmpowered()) and true or false)
            row._cancel:ClearAllPoints()
            row._cancel:SetPoint("RIGHT", row, "RIGHT", right, 0)
            right = right - LAYOUT.search.action.size - LAYOUT.search.action.gap
        end
        -- The word on the accent while the application is live, else dim;
        -- with a countdown the two stack on the row's middle
        local sr, sg, sb
        if lit then sr, sg, sb = theme:GetAccentColor() else sr, sg, sb = theme:GetDimTextColor() end
        row._status:SetTextColor(sr, sg, sb, 1)
        row._status:SetText(text)
        row._status:ClearAllPoints()
        if pending and appDuration then
            local gap = LAYOUT.search.statusGap
            row._expiration = GetTime() + appDuration
            Timer(row)
            row._status:SetPoint("BOTTOMRIGHT", row, "RIGHT", right, gap / 2)
            row._timer:ClearAllPoints()
            row._timer:SetPoint("TOP", row._status, "BOTTOM", 0, -gap)
            row._timer:Show()
            panel:StartTicker()
        else
            row._status:SetPoint("RIGHT", row, "RIGHT", right, 0)
            row._timer:Hide()
        end
        row._status:Show()
    else
        row._status:Hide()
        row._timer:Hide()
        row._cancel:Hide()
        RenderRoster(row, id, info, counts, dimmed)
        row._quickHidden = isDelisted
        SetQuick(row)
    end

    row._voice:SetShown(NonEmpty(info.voiceChat))

    -- The wash in Blizzard's order: red for a group off the filter, the
    -- accent under a live application, dim under a declined one
    local wash
    if offFilter then
        wash = OFF_FILTER_WASH
    elseif isApplication and not isAppFinished then
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
    Host.DressHolder(holder, UI.FieldFill())
    holder:SetHeight(L.rowHeight)
    holder:SetPoint("TOPLEFT", panel, "TOPLEFT", boxX, -L.rowY)
    holder:SetPoint("RIGHT", panel._refresh, "LEFT", -L.gap, 0)
    panel._holder = holder
    panel._clear = UI.AccentText(holder, "label")
    panel._clear:SetText("x")
    panel._clear:SetAlpha(0.75)
    panel._clear:Hide()

    -- The results. The box draws neither its gray nor its border: the
    -- fields carry the gray, and the border closes round the results alone,
    -- with the role column outside it at the box's right
    local box = UI.MakeBox(panel, L.boxTop)
    box._bg:Hide()
    for _, edge in pairs(box._border) do edge:Hide() end
    panel._box = box
    local results = CreateFrame("Frame", nil, box)
    results:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    results:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -L.roles.width, 0)
    results._border = C.CreateBorder(results, {
        thickness = (M().collapsible or {}).borderWidth or 1,
        alpha = (M().collapsible or {}).borderAlpha or 0.6,
        corners = "overlap",
    })
    panel._results = results
    local list = C.CreateScrollList({
        parent = box,
        rowHeight = R.top + R.lines * R.lineHeight + R.bottom,
        createRow = function(row) CreateRow(panel, row) end,
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
    -- The rows end short of the results' border, left of the role column
    local rightPad = pad + L.roles.width
    list.frame:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -pad)
    list.frame:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -rightPad, pad)
    panel._list = list

    panel._empty = C.CreateEmptyState({ parent = box, text = "" })
    panel._empty:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -pad)
    panel._empty:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -rightPad, pad)
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
    panel._sweep:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -rightPad, pad)
    panel._sweep:SetFrameLevel(list.frame:GetFrameLevel() + 10)

    -- The role column: the roles and the note every application carries
    panel._roles = UI.Roles.Build(box, { onChange = function() panel:RefreshButtons() end })

    -- The bottom edge: Back, or Back to Group, and Save Search across from
    -- it, which puts the search as it stands into the tray's list
    -- (saved.lua), off with the reason in its tooltip
    panel._back = UI.MakeButton(panel, Str("BACK", "Back"), function() panel:Back() end, LAYOUT.buttonWidth)
    panel._back:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LAYOUT.panel.buttonX, LAYOUT.panel.buttonY)

    panel._save = UI.MakeButton(panel, "Save Search", function() panel:SaveSearch() end, LAYOUT.buttonWidth,
        function() return panel._saveReason end)
    panel._save:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LAYOUT.panel.buttonX, LAYOUT.panel.buttonY)

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
        captionSize = L.filterCaptionSize,
        captionTop = L.filterCaptionTop,
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
            -- The text is part of what Save Search would save and what the
            -- tray marks as the current search
            GF.Notify("filter")
        end)
        if clearButton then
            -- The x comes up under the cursor, as the button's own icon would
            clearButton:HookScript("OnEnter", function() self._clear:SetAlpha(1) end)
            clearButton:HookScript("OnLeave", function() self._clear:SetAlpha(0.75) end)
        end
        editBox:HookScript("OnEditFocusGained", function() self:RefreshAuto() end)
        -- The box loses focus on the press of a click on the list, before
        -- the release a row's click needs, so a list closed here would go
        -- out from under the cursor with the row unclicked. The list stays
        -- while the cursor is over it; the row's click closes it, and so
        -- does a click outside
        editBox:HookScript("OnEditFocusLost", function()
            if self._auto:IsShown() and self._auto.frame:IsMouseOver() then return end
            self._auto:Close()
        end)
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

    -- An auto-complete row: Blizzard's own fill, SetSearchToActivity,
    -- which puts the activity's full name in the box as Blizzard's row
    -- does (LFGListSearchAutoCompleteButton_OnClick), and the search from
    -- the same click. The focus goes first, so the text change the fill
    -- raises closes the list in place of reopening it under the cursor.
    -- The box's text is what the server searches, so text typed after the
    -- name narrows the search, as Blizzard's key range tip says. A pick
    -- inside the three seconds after a search fills the box and leaves the
    -- search to the arrow or Enter, whose tooltip counts the wait down:
    -- Search is restricted, and a timer's call has no click behind it.
    function panel:PickActivity(key)
        if key == "more" then return end
        local sp = SearchPanel()
        if not (sp and LFGListSearchPanel_DoSearch) then return end
        if sp.SearchBox then sp.SearchBox:ClearFocus() end
        C_LFGList.SetSearchToActivity(key)
        if GF.SearchAllowed() then
            self:DoSearch()
        else
            self:RefreshButtons()
        end
    end

    ----------------------------------------------------------------------------
    -- Searching: Blizzard's DoSearch from the panel's state and the box's
    -- text, which the host's hook notes, from the arrow, from a pick, and
    -- from Enter in the box through Blizzard's own handler
    ----------------------------------------------------------------------------

    function panel:DoSearch()
        local sp = SearchPanel()
        if sp and LFGListSearchPanel_DoSearch then LFGListSearchPanel_DoSearch(sp) end
    end

    function panel:Search()
        if not GF.SearchAllowed() then
            self:RefreshButtons()
            return
        end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        self:DoSearch()
    end

    -- Back to Group while the leader's listing is up, as Blizzard's panel
    -- swaps the button; the plain Back drops the rows, as Blizzard's Clear
    -- does, so the next Find Group starts from an empty pane and not
    -- another category's rows
    function panel:RefreshBack()
        local listed = GF.HasEntry() and UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME)
        self._toGroup = listed and true or false
        if self._toGroup then
            self._back:SetText(Str("GROUP_FINDER_BACK_TO_GROUP", "Back to Group"))
        else
            self._back:SetText(Str("BACK", "Back"))
        end
    end

    -- Save Search: the search as it stands into the character's list; the
    -- tray takes it from there. Off with the reason in its tooltip: the
    -- list is full, or the same search is saved already
    function panel:SaveSearch()
        if not UI.Saved or UI.Saved:SaveBlock() then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        UI.Saved:SaveCurrent()
        self:RefreshSave()
    end

    function panel:RefreshSave()
        local reason = UI.Saved and UI.Saved:SaveBlock() or nil
        self._saveReason = reason
        self._save:SetEnabled(UI.Saved ~= nil and reason == nil)
    end

    function panel:Back()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if not self._toGroup then
            GF.state.selectedResult = nil
            GF.state.results = {}
            self._list:SetItems({})
            self._sweep:Stop()
            self._drawer:Close(true)
        end
        Search:Close()
        UI:SetView(nil)
    end

    -- The one protected call, from the row's click: the roles the column
    -- holds, and the note the C side reads from the hosted box. The row
    -- redraws as the application's status lands.
    function panel:Apply(id)
        if not id or not GF.CanSelect(id) then return end
        if GF.SignUpBlock() or not UI.Roles:HasRole() then return end
        local tank, healer, damage = UI.Roles:GetRoles()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        C_LFGList.ApplyToGroup(id, tank, healer, damage)
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

    -- The dungeons the filter lists are GF.DungeonGroups (the component's
    -- saved.lua), shared with the saved searches' summary and replay

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
            local season, expansion, timerunning = GF.DungeonGroups()
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
                local _, _, _, ids = GF.DungeonGroups()
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
            GF.Notify("filter")
            return
        end
        if not C_LFGList.SaveLanguageSearchFilter then return end
        local enabled = C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter() or {}
        enabled[key] = checked and true or false
        C_LFGList.SaveLanguageSearchFilter(enabled)
        GF.Notify("filter")
    end

    -- Select all writes every dungeon; Unselect all writes none, which the
    -- search reads as no dungeon filter, and the rows show it as the
    -- player left it until a dungeon is checked or the drawer opens again
    function panel:SetAllDungeons(on)
        local enabled = C_LFGList.GetAdvancedFilter()
        if type(enabled) ~= "table" then return end
        local _, _, _, ids = GF.DungeonGroups()
        enabled.activities = on and ids or {}
        self._dungeonsCleared = not on
        C_LFGList.SaveAdvancedFilter(enabled)
        self._list:Refresh()
        self._filterList:Refresh()
        GF.Notify("filter")
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

    -- Blizzard's search-entry tooltip, LFGListUtil_SetSearchEntryTooltip
    -- (LFGList.lua) line for line in its order and colors. The builder itself
    -- cannot be called: it asks the protected GetPlaystyleString for the
    -- playstyle, which the enum's own strings answer here. Each block runs
    -- in its own pcall, so a field that is secret under the chat lockdown
    -- drops its block and the rest still draws.
    function panel:ShowTooltip(row, id)
        local info = GF.ResultInfo(id)
        if not info then return end
        local tooltip = GameTooltip
        tooltip:SetOwner(row, "ANCHOR_RIGHT", 25, 0)
        tooltip:ClearLines()

        local activityID = GF.ActivityID(info)
        local isWarMode = GF.plainBool(info.isWarMode)
        local okA, activity = pcall(C_LFGList.GetActivityInfoTable, activityID, nil, isWarMode)
        if not okA or type(activity) ~= "table" then activity = {} end
        local censored = GF.plainBool(info.censored) == true
        local crossFaction = GF.plainBool(info.crossFactionListing) == true
        local numMembers = GF.plainNumber(info.numMembers) or 0
        local factionString = FACTION_STRINGS and FACTION_STRINGS[GF.plainNumber(info.leaderFactionGroup) or -1]

        local allowsCrossFaction = false
        pcall(function()
            local category = activity.categoryID and C_LFGList.GetLfgCategoryInfo(activity.categoryID)
            allowsCrossFaction = (category and category.allowCrossFaction and activity.allowCrossFaction) and true or false
        end)
        local showFaction = not crossFaction and allowsCrossFaction and factionString

        -- Name, activity, playstyle
        pcall(function()
            if censored then
                GameTooltip_AddHighlightLine(tooltip, RED_FONT_COLOR:WrapTextInColorCode(Str("CENSORED_LFG_GROUP_NAME")), true)
            elseif type(info.name) == "string" then
                GameTooltip_AddHighlightLine(tooltip, info.name, true)
            end
        end)
        pcall(function()
            if type(activity.fullName) == "string" then tooltip:AddLine(activity.fullName) end
        end)
        pcall(function()
            local playstyle = GF.GeneralPlaystyleString(GF.plainNumber(info.generalPlaystyle))
            if showFaction then
                GameTooltip_AddColoredLine(tooltip, Str("GROUP_FINDER_CROSS_FACTION_LISTING_WITH_PLAYSTLE"):format(playstyle, factionString), GREEN_FONT_COLOR)
                GameTooltip_AddColoredLine(tooltip, Str("GROUP_FINDER_CROSS_FACTION_LISTING_WITHOUT_PLAYSTLE"):format(factionString), GREEN_FONT_COLOR)
            else
                GameTooltip_AddColoredLine(tooltip, playstyle, GREEN_FONT_COLOR)
            end
        end)

        -- The comment, or the quest's description when a quest group has none
        pcall(function()
            local c = LFG_LIST_COMMENT_FONT_COLOR
            if censored then
                tooltip:AddLine(Str("CENSORED_LFG_COMMENT"), c.r, c.g, c.b, true)
                return
            end
            local comment = info.comment
            if type(comment) ~= "string" or GF.plain(comment) == nil then return end
            -- A kstring comment does not compare, so it counts as written
            local readable = pcall(function() return comment == "" end)
            local questID = GF.plainNumber(info.questID)
            if readable and comment == "" and questID and LFGListUtil_GetQuestDescription then
                comment = LFGListUtil_GetQuestDescription(questID)
                if not NonEmpty(comment) then return end
            elseif readable and not NonEmpty(comment) then
                return
            end
            -- The format may refuse a kstring; then the comment draws as it is
            local okF, text = pcall(string.format, Str("LFG_LIST_COMMENT_FORMAT", "\"%s\""), comment)
            tooltip:AddLine(okF and text or comment, c.r, c.g, c.b, true)
        end)

        -- Requirements and voice chat, with a blank after them when any drew
        tooltip:AddLine(" ")
        pcall(function()
            local score = GF.plainNumber(info.requiredDungeonScore) or 0
            local pvp = GF.plainNumber(info.requiredPvpRating) or 0
            local ilvl = GF.plainNumber(info.requiredItemLevel) or 0
            local honor = activity.useHonorLevel and (GF.plainNumber(info.requiredHonorLevel) or 0) or 0
            local voice = NonEmpty(info.voiceChat)
            if score > 0 then tooltip:AddLine(Str("GROUP_FINDER_MYTHIC_RATING_REQ_TOOLTIP"):format(score)) end
            if pvp > 0 then tooltip:AddLine(Str("GROUP_FINDER_PVP_RATING_REQ_TOOLTIP"):format(pvp)) end
            if ilvl > 0 then
                local key = activity.isPvpActivity and "LFG_LIST_TOOLTIP_ILVL_PVP" or "LFG_LIST_TOOLTIP_ILVL"
                tooltip:AddLine(Str(key):format(ilvl))
            end
            if honor > 0 then tooltip:AddLine(Str("LFG_LIST_TOOLTIP_HONOR_LEVEL"):format(honor)) end
            if voice then tooltip:AddLine(string.format(Str("LFG_LIST_TOOLTIP_VOICE_CHAT"), info.voiceChat), nil, nil, nil, true) end
            if score > 0 or pvp > 0 or ilvl > 0 or honor > 0 or voice then tooltip:AddLine(" ") end
        end)

        -- The leader, with the Mythic+ score block or the rated PvP line
        local leaderName = SS.plainString(info.leaderName)
        pcall(function()
            if not leaderName then return end
            local leaderString = leaderName
            local myFaction = UnitFactionGroup("player")
            local leaderFaction = PLAYER_FACTION_GROUP and PLAYER_FACTION_GROUP[GF.plainNumber(info.leaderFactionGroup) or -1]
            if factionString and myFaction ~= leaderFaction then
                leaderString = Str("LFG_LIST_TOOLTIP_LEADER_FACTION"):format(leaderName, factionString)
            end
            local overall = GF.plainNumber(info.leaderOverallDungeonScore)
            if activity.isMythicPlusActivity and overall then
                local overallColor = C_ChallengeMode.GetDungeonScoreRarityColor(overall) or HIGHLIGHT_FONT_COLOR
                tooltip:AddDoubleLine(leaderString, overallColor:WrapTextInColorCode(overall))
                local scores = info.leaderDungeonScoreInfo
                local forDungeon = type(scores) == "table" and scores[1]
                if type(forDungeon) == "table" then
                    tooltip:AddDoubleLine(Str("LFG_LIST_BEST_FOR_DUNGEON"), RunLevelText(forDungeon))
                end
                if type(info.leaderBestDungeonScoreInfo) == "table" then
                    tooltip:AddDoubleLine(Str("LFG_LIST_BEST_RUN"), RunLevelText(info.leaderBestDungeonScoreInfo))
                end
            else
                tooltip:AddLine(leaderString)
            end
        end)
        pcall(function()
            local ratings = info.leaderPvpRatingInfo
            if not activity.isRatedPvpActivity or type(ratings) ~= "table" or #ratings == 0 then return end
            local r = ratings[1]
            GameTooltip_AddNormalLine(tooltip, Str("PVP_RATING_GROUP_FINDER"):format(r.activityName, r.rating, PVPUtil.GetTierName(r.tier)))
        end)
        if leaderName or (GF.plainNumber(info.age) or 0) > 0 then tooltip:AddLine(" ") end

        -- The members one per line, as Blizzard lists them only when every
        -- member answers with a role; else the counts
        local groupHasLeaver = false
        pcall(function()
            local members, complete = {}, false
            local displayType = activity.displayType
            local D = Enum.LFGListDisplayType
            if displayType == D.ClassEnumerate or displayType == D.RoleEnumerate then
                members, complete = GF.Members(id, numMembers)
            end
            for _, m in ipairs(members) do
                if m.leaver then groupHasLeaver = true end
            end
            if complete then
                tooltip:AddLine(Str("MEMBERS_COLON"))
                local leaderIcon = CreateAtlasMarkup("groupfinder-icon-leader", 14, 9, 0, 0)
                for _, m in ipairs(members) do
                    local r, g, b = NORMAL_FONT_COLOR:GetRGB()
                    if m.class then
                        local cr, cg, cb = addon.GetClassColorRGB(m.class)
                        if cr then r, g, b = cr, cg, cb end
                    end
                    local roleIcon = CreateAtlasMarkup(ROLE_ATLASES_BORDERLESS[m.role] or "", 13, 13, 0, 0)
                    local text = roleIcon .. " " .. string.format(Str("LFG_LIST_TOOLTIP_CLASS_ROLE"), m.className or "", m.spec or "")
                    if m.leader then text = text .. " " .. leaderIcon end
                    if m.leaver then text = text .. " " .. CreateAtlasMarkup("groupfinder-icon-leaver", 12, 12, 0, 0) end
                    tooltip:AddLine(text, r, g, b)
                end
            else
                local counts = GF.MemberCounts(id) or {}
                tooltip:AddLine(string.format(Str("LFG_LIST_TOOLTIP_MEMBERS"), numMembers,
                    GF.plainNumber(counts.TANK) or 0, GF.plainNumber(counts.HEALER) or 0,
                    GF.plainNumber(counts.DAMAGER) or 0))
            end
        end)

        -- Friends, bosses defeated, auto-accept, delisted, the leaver warning
        pcall(function()
            local friends = (GF.plainNumber(info.numBNetFriends) or 0) + (GF.plainNumber(info.numCharFriends) or 0)
                + (GF.plainNumber(info.numGuildMates) or 0)
            if friends > 0 then
                tooltip:AddLine(" ")
                tooltip:AddLine(Str("LFG_LIST_TOOLTIP_FRIENDS_IN_GROUP"))
                tooltip:AddLine(LFGListSearchEntryUtil_GetFriendList(id), 1, 1, 1, true)
            end
        end)
        pcall(function()
            local encounters = C_LFGList.GetSearchResultEncounterInfo(id)
            if type(encounters) ~= "table" or #encounters == 0 then return end
            tooltip:AddLine(" ")
            tooltip:AddLine(Str("LFG_LIST_BOSSES_DEFEATED"))
            for i = 1, #encounters do
                tooltip:AddLine(encounters[i], RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
            end
        end)
        pcall(function()
            if GF.plainBool(info.autoAccept) then
                tooltip:AddLine(" ")
                tooltip:AddLine(Str("LFG_LIST_TOOLTIP_AUTO_ACCEPT"), LIGHTBLUE_FONT_COLOR:GetRGB())
            end
            if GF.plainBool(info.isDelisted) then
                tooltip:AddLine(" ")
                tooltip:AddLine(Str("LFG_LIST_ENTRY_DELISTED"), RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
            end
            if groupHasLeaver then
                GameTooltip_AddBlankLineToTooltip(tooltip)
                GameTooltip_AddErrorLine(tooltip, Str("MYTHIC_PLUS_DESERTER_GROUP_WARNING"))
            end
        end)

        tooltip:Show()
        if addon.Tooltip and addon.Tooltip.StyleDirect then addon.Tooltip.StyleDirect() end
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
        for _, id in ipairs(state.results) do
            items[#items + 1] = { resultID = id }
        end
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

    -- The rows' sign-up buttons follow the chain and the roles without a
    -- redraw of the rows
    function panel:RefreshQuick()
        for i = 1, #self._list._items do
            local row = self._list:GetRow(i)
            if row and row:IsShown() and row._resultID then SetQuick(row) end
        end
    end

    function panel:RefreshButtons()
        self._start:SetEnabled(GF.StartGroupBlock() == nil)
        self:RefreshBack()
        self:RefreshSave()
        local allowed = GF.SearchAllowed()
        self._refresh:SetEnabled(allowed)
        if not allowed then
            C_Timer.After(GF.SearchCooldownLeft() + 0.05, function()
                if self:IsShown() then self:RefreshButtons() end
            end)
        end
        self:RefreshQuick()
    end

    function panel:Refresh()
        self:RefreshHeading()
        self:RefreshLayout()
        self:TakeBox()
        UI.Roles:Refresh()
        UI.Roles:TakeNote()
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
        UI.Roles:ReleaseNote()
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
    -- The client's role update, after the column wrote a choice or another
    -- of Blizzard's role buttons did
    GF.Listen("roles", function()
        if panel:IsShown() then panel:RefreshButtons() end
    end)
    GF.Listen("entry", function()
        if panel:IsShown() then panel:RefreshButtons() end
    end)
    GF.Listen("lockdown", function()
        if panel:IsShown() then panel:RefreshList() end
    end)
    -- A filter toggle or the box's text: what Save Search would save changed
    GF.Listen("filter", function()
        if panel:IsShown() then panel:RefreshSave() end
    end)
    GF.Listen("saved", function()
        if panel:IsShown() then panel:RefreshSave() end
    end)

    return panel
end

UI.panelBuilders.search = Build
