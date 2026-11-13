--------------------------------------------------------------------------------
-- forever/groupfinder/browse.lua
-- The Browse tab: pick a category and activities, search, read the results,
-- whisper or invite. A port of Blizzard's LFGBrowseFrame onto the window's
-- own frames and its own search state.
--
-- The rows, the two headers, the options button and the spinner are Blizzard's
-- templates; a row's scripts are replaced, since Blizzard's read its own
-- frame's filter and selection. Two of Blizzard's functions are called as
-- they stand, each on a frame of this file's and reading no frame of
-- Blizzard's: the one that draws a row's members and the one that fills the
-- tooltip. The tooltip is this file's frame with the parts that function
-- names.
--
-- Search is a restricted call, made by a click: a category picked, an
-- activity group checked, the refresh button, the self listing radio. A new
-- listing is searched by Blizzard's hidden frame, and this tab reads the
-- answer.
--------------------------------------------------------------------------------

local addonName, addon = ...

local LFG = addon.ForeverGroupFinder
local Data = LFG.Data
local UI = LFG.UI

local Browse = {}
LFG.Browse = Browse

local B = LFG.LAYOUT.browse

local DIVIDER_SOLO, DIVIDER_GROUP = 1, 2
local DELISTED = { r = 0.3, g = 0.3, b = 0.3 }

-- What the tab searches for: a category id (0 is none) and the activity ids
-- checked in the filter, in the order checked
local search = { category = 0, activities = {} }

local tab                   -- the tab's frame, nil until built
local P = {}                -- its parts by name
local total, results = 0, {}
local selectedID
local tooltip
local tooltipError

--------------------------------------------------------------------------------
-- The filter's activities
--------------------------------------------------------------------------------

local function IsActivitySelected(activityID)
    for i = 1, #search.activities do
        if search.activities[i] == activityID then return true end
    end
    return false
end

local function SetActivitySelected(activityID, on)
    for i = #search.activities, 1, -1 do
        if search.activities[i] == activityID then
            if on then return end
            table.remove(search.activities, i)
        end
    end
    if on then search.activities[#search.activities + 1] = activityID end
end

local function IsAnyInGroupSelected(groupID)
    if search.category <= 0 then return false end
    for _, id in ipairs(Data.FilteredActivities(search.category)) do
        if Data.ActivityGroup(id) == groupID and IsActivitySelected(id) then return true end
    end
    return false
end

local function SetAllInGroup(groupID, on)
    if search.category <= 0 then return end
    for _, id in ipairs(Data.FilteredActivities(search.category)) do
        if Data.ActivityGroup(id) == groupID then SetActivitySelected(id, on) end
    end
end

-- The filter set to a list of activities: the first one's category and
-- those of the list in that category
local function SelectActivities(activityIDs)
    wipe(search.activities)
    local first = 0
    for _, id in ipairs(activityIDs) do
        local info = id ~= 0 and Data.ActivityInfo(id)
        if info then
            if first == 0 then
                first = info.categoryID
                search.category = first
            end
            if info.categoryID == first then SetActivitySelected(id, true) end
        end
    end
    return first ~= 0
end

-- The filter set to the player's own listing
local function SelectEntryActivities()
    local entry = Data.Entry()
    if not entry then return false end
    return SelectActivities(entry.activityIDs)
end

--------------------------------------------------------------------------------
-- Searching
--------------------------------------------------------------------------------

local function DoSearch()
    local ids = {}
    for i = 1, #search.activities do ids[i] = search.activities[i] end
    Data.Search(search.category, ids)
end

--------------------------------------------------------------------------------
-- Buttons' state
--------------------------------------------------------------------------------

local function UpdateButtons()
    if not tab then return end
    local has = selectedID ~= nil
    P.message:SetEnabled(has)
    P.invite:SetEnabled(has and Data.CanInviteResult(selectedID))
    P.refresh:SetEnabled(not Data.searching)
end

--------------------------------------------------------------------------------
-- The tooltip
--------------------------------------------------------------------------------

-- A frame with the parts LFGBrowseSearchEntryTooltip_UpdateAndShow names, as
-- Blizzard's XML lays them out
local function BuildTooltip()
    local t = B.tooltip
    local tip = CreateFrame("Frame", nil, UIParent, "TooltipBackdropTemplate")
    tip:SetFrameStrata("TOOLTIP")
    tip:SetClampedToScreen(true)
    tip:SetSize(t.width, 1)
    tip:Hide()

    local delisted = tip:CreateFontString(nil, "ARTWORK", "GameFontRed")
    delisted:SetJustifyH("LEFT")
    delisted:SetText(LFG_LIST_ENTRY_DELISTED)
    delisted:SetPoint("TOPLEFT", tip, "TOPLEFT", t.pad, -10)
    tip.Delisted = delisted

    local newIcon = tip:CreateTexture(nil, "ARTWORK")
    newIcon:SetAtlas("newplayerchat-chaticon-newcomer", true)
    newIcon:SetPoint("TOPLEFT", tip, "TOPLEFT", t.pad, -10)
    tip.NewPlayerFriendlyIcon = newIcon

    local newText = tip:CreateFontString(nil, "ARTWORK", "GameFontGreen")
    newText:SetJustifyH("LEFT")
    newText:SetText(LFG_LIST_NEW_PLAYER_FRIENDLY_HEADER)
    newText:SetPoint("TOPLEFT", newIcon, "TOPRIGHT", 1, -2)
    tip.NewPlayerFriendlyText = newText

    local leaderIcon = tip:CreateTexture(nil, "ARTWORK")
    leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    leaderIcon:SetSize(t.leaderIcon, t.leaderIcon)
    leaderIcon:SetPoint("TOPLEFT", tip, "TOPLEFT", t.pad, -10)
    tip.LeaderIcon = leaderIcon

    local comment = tip:CreateFontString(nil, "ARTWORK", "GameFontNormalLeftLightGrey")
    comment:SetJustifyV("TOP")
    comment:SetJustifyH("LEFT")
    comment:SetWordWrap(true)
    comment:SetPoint("LEFT", tip, "LEFT", t.pad, 0)
    comment:SetPoint("RIGHT", tip, "RIGHT", -t.pad, 0)
    tip.Comment = comment

    local memberCount = tip:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    memberCount:SetJustifyH("LEFT")
    memberCount:SetPoint("TOPLEFT", comment, "BOTTOMLEFT", 0, -8)
    tip.MemberCount = memberCount

    local header = tip:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetJustifyH("LEFT")
    header:SetText(LFG_LIST_BOSSES_DEFEATED)
    tip.CompletedEncounterHeader = header

    local voice = tip:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    voice:SetJustifyH("LEFT")
    voice:SetWordWrap(false)
    voice:SetPoint("TOPLEFT", memberCount, "BOTTOMLEFT", 0, -8)
    voice:Hide()
    tip.VoiceChat = voice

    local leader = CreateFrame("Frame", nil, tip, "LFGBrowseSearchEntryTooltipGroupLeader")
    leader:SetPoint("TOPLEFT", leaderIcon, "TOPRIGHT", 0, -2)
    tip.Leader = leader

    tip.memberPool = CreateFramePool("FRAME", tip, "LFGBrowseSearchEntryTooltipGroupMember")
    tip.activityPool = CreateFontStringPool(tip, "ARTWORK", 0, "LFGBrowseSearchEntryTooltipActivityNameTemplate")
    tip.completedEncounterPool = CreateFontStringPool(tip, "ARTWORK", 0,
        "LFGBrowseSearchEntryTooltipCompletedEncounterTemplate")
    return tip
end

local function HideTooltip()
    if tooltip then tooltip:Hide() end
end

local function ShowTooltip(row)
    if not (LFGBrowseSearchEntryTooltip_UpdateAndShow and Data.Result(row.resultID)) then return end
    if not tooltip then
        local ok, made = pcall(BuildTooltip)
        if not ok then
            tooltipError = made
            return
        end
        tooltip = made
    end
    local ok, err = pcall(LFGBrowseSearchEntryTooltip_UpdateAndShow, tooltip, row.resultID)
    if not ok then
        tooltipError = err
        tooltip:Hide()
        return
    end
    tooltip:ClearAllPoints()
    tooltip:SetPoint("TOPLEFT", row, "TOPRIGHT", B.tooltip.x, B.tooltip.y)
end

--------------------------------------------------------------------------------
-- A result's row
--------------------------------------------------------------------------------

local function SetRowSelection(row, selected)
    row.Selected:SetShown(selected)
    if selected then
        row.Highlight:Hide()
    elseif row:IsMouseOver() then
        row.Highlight:Show()
    end
end

local function ForEachResultRow(fn)
    if not (tab and P.scrollBox.ForEachFrame) then return end
    P.scrollBox:ForEachFrame(function(row)
        if row.resultID then fn(row) end
    end)
end

local function SetSelection(resultID)
    selectedID = resultID
    ForEachResultRow(function(row)
        SetRowSelection(row, row.resultID == selectedID)
    end)
    UpdateButtons()
end

-- A selection whose listing has gone is dropped
local function ValidateSelection()
    if not selectedID then return end
    local info = Data.Result(selectedID)
    if not info or info.isDelisted then SetSelection(nil) end
end

local function SetColor(fontString, color)
    fontString:SetTextColor(color.r, color.g, color.b)
end

local function OnRowEnter(row)
    ShowTooltip(row)
    if not row.Selected:IsShown() then row.Highlight:Show() end
end

local function OnRowLeave(row)
    HideTooltip()
    row.Highlight:Hide()
end

-- Blizzard's LFGBrowseSearchEntry_Update, read against this tab's filter
local function UpdateRow(row)
    local info = Data.Result(row.resultID)
    if not info then
        row:Hide()
        return
    end
    row:Show()

    local entry = Data.Entry()
    local solo = info.numMembers == 1
    local soloRoles
    if solo then
        row.PartyIcon:Hide()
        row.ClassIcon:Show()
        row.Level:Show()
        local member = Data.ResultMember(row.resultID, 1)
        if member and member.classFilename and member.level then
            row.Level:SetText(LEVEL_ABBR .. " " .. member.level)
            row.ClassIcon:SetAtlas("groupfinder-icon-class-" .. string.lower(member.classFilename), false)
        else
            row.Level:Hide()
            row.ClassIcon:Hide()
        end
        row.Name:SetPoint("TOPLEFT", row.PartyIcon, "TOPLEFT", row.NameSoloOffsetX, row.NameSoloOffsetY)
        row.NewPlayerFriendlyIcon:SetPoint("LEFT", row.ClassIcon, "RIGHT", 2, 0)
        soloRoles = member and member.lfgRoles
    else
        row.PartyIcon:Show()
        row.Level:Hide()
        row.ClassIcon:Hide()
        row.Name:SetPoint("TOPLEFT", row.PartyIcon, "TOPRIGHT", row.NameGroupOffsetX, row.NameGroupOffsetY)
        row.NewPlayerFriendlyIcon:SetPoint("LEFT", row.DiscordIcon or row.Name, "RIGHT", 2, 0)
    end

    row.isDelisted = info.isDelisted and true or false
    row.hasSelf = info.hasSelf and true or false

    local matching = Data.MatchingActivities(info, entry)
    local hasMatch = #matching > 0
    local shown = hasMatch and matching or info.activityIDs
    local activityText
    if info.hasSelf then
        activityText = LFG_SELF_LISTING
    elseif #shown == 1 then
        activityText = Data.ActivityName(Data.ActivityInfo(shown[1]))
    else
        activityText = string.format(hasMatch and LFGBROWSE_ACTIVITY_MATCHING_COUNT or LFGBROWSE_ACTIVITY_COUNT,
            #shown)
    end

    local matchesFilter = true
    if #search.activities > 0 then
        matchesFilter = false
        for _, id in ipairs(info.activityIDs) do
            if IsActivitySelected(id) then
                matchesFilter = true
                break
            end
        end
    end

    local leader = Data.ResultLeader(row.resultID)
    local nameColor = NORMAL_FONT_COLOR
    if leader and leader.classFilename then
        nameColor = addon.GetClassColorObj(leader.classFilename) or nameColor
    end
    local levelColor = GRAY_FONT_COLOR
    local activityColor = GRAY_FONT_COLOR
    if info.isDelisted or not matchesFilter then
        nameColor, levelColor, activityColor = DELISTED, DELISTED, DELISTED
    elseif info.hasSelf then
        activityColor = LIGHTGREEN_FONT_COLOR
    elseif hasMatch then
        activityColor = BRIGHTBLUE_FONT_COLOR
    end

    row.Name:SetWidth(0)
    row.Name:SetText(info.leaderName)
    SetColor(row.Name, nameColor)
    local nameMax = row.NameMaxWidth or 200
    if row.DiscordIcon then
        local modes = Enum.LFGEntryVoiceMode
        local discord = modes ~= nil and info.voiceMode == modes.Discord
        row.DiscordIcon:SetShown(discord)
        row.DiscordIcon:SetDesaturated(row.isDelisted)
        if discord then
            nameMax = nameMax - row.DiscordIcon:GetWidth() - 4
            row.Level:SetPoint("BOTTOMLEFT", row.DiscordIcon, "BOTTOMRIGHT", 4, 0)
        else
            row.Level:SetPoint("BOTTOMLEFT", row.Name, "BOTTOMRIGHT", 4, 0)
        end
    end

    SetColor(row.Level, levelColor)
    row.ClassIcon:SetDesaturated(row.isDelisted)
    row.ActivityName:SetText(activityText)
    SetColor(row.ActivityName, activityColor)

    if row.PlaystyleLabel then
        local style = info.generalPlaystyle
        row.PlaystyleLabel:SetText(style and GetGeneralPlaystyleString and GetGeneralPlaystyleString(style) or "")
    end

    if info.newPlayerFriendly then
        row.NewPlayerFriendlyIcon:Show()
        nameMax = nameMax - row.NewPlayerFriendlyIcon:GetWidth() - 1
    else
        row.NewPlayerFriendlyIcon:Hide()
    end
    row.NewPlayerFriendlyIcon:SetDesaturated(row.isDelisted)

    -- The width of a name the addon may not read is cut to the limit unseen
    local ok, fits = pcall(function() return row.Name:GetWidth() <= nameMax end)
    if not (ok and fits) then row.Name:SetWidth(nameMax) end

    if LFGBrowseGroupDataDisplay_Update then
        local displayType, maxPlayers = Data.BestDisplayType(info.activityIDs)
        LFGBrowseGroupDataDisplay_Update(row.DataDisplay, displayType, maxPlayers, Data.ResultCounts(row.resultID),
            row.isDelisted, solo, soloRoles, info.comment, row.hasSelf)
    end

    if row:IsMouseOver() then OnRowEnter(row) end
end

local function OpenRowMenu(row)
    local info = Data.Result(row.resultID)
    if not info then return end
    local resultID, leaderName = row.resultID, info.leaderName
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(leaderName)
        local message = root:CreateButton(SEND_MESSAGE, function()
            ChatFrameUtil.SendTell(leaderName)
        end)
        message:SetEnabled(leaderName ~= nil)
        local invite = root:CreateButton(GROUP_INVITE, function()
            C_PartyInfo.InviteUnit(leaderName)
        end)
        invite:SetEnabled(Data.CanInviteResult(resultID))
        local report = root:CreateButton(LFG_LIST_REPORT_GROUP_FOR, function()
            LFGBrowseUtil_ReportListing(resultID, leaderName)
        end)
        report:SetEnabled(LFGBrowseUtil_ReportListing ~= nil)
        local advert = root:CreateButton(REPORT_GROUP_FINDER_ADVERTISEMENT, function()
            LFGBrowseUtil_ReportAdvertisement(resultID, leaderName)
        end)
        advert:SetEnabled(LFGBrowseUtil_ReportAdvertisement ~= nil)
    end)
end

local function OnRowClick(row, button)
    if row.isDelisted or row.hasSelf then return end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if button == "LeftButton" then
        SetSelection(selectedID ~= row.resultID and row.resultID or nil)
    elseif button == "RightButton" then
        OpenRowMenu(row)
    end
end

-- The x on the player's own row. Blizzard's also searches again; one
-- restricted call a click is the rule here, and the row greys by its event.
local function OnDelistClick()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if Data.HasEntry() then
        Data.RemoveListing()
        UI:SelectTab(1)
    end
end

-- The template's scripts read Blizzard's frame; each is replaced. The event
-- its load registered is dropped, and a changed result comes by the data
-- layer's topic.
local function InitRow(row, data)
    row.resultID = data.resultID
    row.isDelisted = false
    row:UnregisterAllEvents()
    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", OnRowLeave)
    local delist = row.DataDisplay and row.DataDisplay.DelistButton
    if delist then delist:SetScript("OnClick", OnDelistClick) end
    SetRowSelection(row, row.resultID == selectedID)
    UpdateRow(row)
end

local function InitDivider(row, node)
    local data = node:GetData()
    row.resultID = nil
    row.CategoryLabel:Show()
    row.CategoryLabel:SetText(data.dividerType == DIVIDER_SOLO and LFG_LIST_CATEGORY_SOLO_PLAYERS
        or LFG_LIST_CATEGORY_GROUPS)
    local function marks()
        local collapsed = node:IsCollapsed()
        row.ExpandIcon:SetShown(collapsed)
        row.CollapseIcon:SetShown(not collapsed)
    end
    marks()
    row:SetScript("OnClick", function()
        local invalidate = TreeDataProviderConstants and TreeDataProviderConstants.DoInvalidation
        node:ToggleCollapsed(nil, invalidate)
        marks()
    end)
end

--------------------------------------------------------------------------------
-- The result list
--------------------------------------------------------------------------------

local function Grouped()
    return LFGVANILLA_SETTING_BROWSE_SHOW_COLLAPSIBLE_CATEGORIES ~= false
end

-- Blizzard's UpdateResults: the spinner, the empty line, or the rows under
-- their two headers, the player's own listing above both
local function Render()
    if not tab then return end
    selectedID = nil
    HideTooltip()
    if P.scrollBox.RemoveDataProvider then P.scrollBox:RemoveDataProvider() end

    if Data.searching then
        P.spinner:Show()
        P.noResults:Hide()
    else
        P.spinner:Hide()
        if total == 0 or Data.searchFailed then
            P.noResults:SetText(Data.searchFailed and LFG_LIST_SEARCH_FAILED or LFG_LIST_NO_RESULTS_FOUND)
            P.noResults:Show()
        else
            P.noResults:Hide()
            local provider = CreateTreeDataProvider()
            local subtree, current
            for index, resultID in ipairs(results) do
                local info = Data.Result(resultID)
                if info then
                    local divider
                    if not info.hasSelf then
                        divider = (info.numMembers or 0) <= 1 and DIVIDER_SOLO or DIVIDER_GROUP
                    end
                    if Grouped() and divider and divider ~= current then
                        current = divider
                        subtree = provider:Insert({ dividerType = divider })
                    end
                    if subtree then
                        subtree:Insert({ index = index, resultID = resultID, nested = true })
                    else
                        provider:Insert({ index = index, resultID = resultID })
                    end
                end
            end
            local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
            P.scrollBox:SetDataProvider(provider, retain)
        end
    end
    UpdateButtons()
end

local function Rebuild()
    total, results = Data.Results()
    Render()
end

--------------------------------------------------------------------------------
-- The two dropdowns
--------------------------------------------------------------------------------

local RefreshDropdowns

local function UpdateActivityHeader()
    local dropdown = P.activity
    if not (dropdown and dropdown.OverrideText) then return end
    local n = #search.activities
    if n == 0 then
        dropdown:OverrideText(LFGBROWSE_ACTIVITY_HEADER_DEFAULT)
    elseif n == 1 then
        dropdown:OverrideText(Data.ActivityName(Data.ActivityInfo(search.activities[1])))
    else
        dropdown:OverrideText(string.format(LFGBROWSE_ACTIVITY_HEADER, n))
    end
end

local function SetupCategoryMenu()
    P.category:SetupMenu(function(_, root)
        local function isSelected(value) return search.category == value end
        local function setSelected(value)
            search.category = value
            wipe(search.activities)
            RefreshDropdowns()
            DoSearch()
        end
        local categories = Data.Categories()
        local listed = Data.HasEntry()
        if #categories == 0 and not listed then
            root:CreateRadio(LFG_TYPE_NONE, function() return false end, function() end)
            return
        end
        if listed then
            root:CreateRadio(LFG_SELF_LISTING, function() return false end, function()
                SelectEntryActivities()
                RefreshDropdowns()
                DoSearch()
            end)
        end
        for _, category in ipairs(categories) do
            root:CreateRadio(category.name, isSelected, setSelected, category.id)
        end
    end)
end

local function SetupActivityMenu()
    P.activity:SetupMenu(function(_, root)
        if search.category <= 0 then return end
        local ids = Data.FilteredActivities(search.category)
        if #ids == 0 then return end
        local function toggle(activityID)
            SetActivitySelected(activityID, not IsActivitySelected(activityID))
            UpdateActivityHeader()
        end
        local function toggleGroup(groupID)
            SetAllInGroup(groupID, not IsAnyInGroupSelected(groupID))
            UpdateActivityHeader()
            DoSearch()
        end
        local byGroup, groupIDs = Data.ActivitiesByGroup(ids)
        for _, groupID in ipairs(groupIDs) do
            if groupID == 0 then
                for _, id in ipairs(byGroup[groupID]) do
                    root:CreateCheckbox(Data.ActivityName(Data.ActivityInfo(id)), IsActivitySelected, toggle, id)
                end
            else
                local groupName = C_LFGList.GetActivityGroupInfo(groupID) or ""
                local groupBox = root:CreateCheckbox(groupName, IsAnyInGroupSelected, toggleGroup, groupID)
                -- One group: its activities indented under it. Several: each
                -- group's in a menu of its own.
                local parent, indent = root, LFG_LIST_INDENT
                if #groupIDs > 1 then parent, indent = groupBox, "%s" end
                for _, id in ipairs(byGroup[groupID]) do
                    local name = string.format(indent, Data.ActivityName(Data.ActivityInfo(id)))
                    parent:CreateCheckbox(name, IsActivitySelected, toggle, id)
                end
            end
        end
    end)
end

RefreshDropdowns = function()
    if not tab then return end
    if search.category <= 0 then wipe(search.activities) end
    SetupCategoryMenu()
    SetupActivityMenu()
    P.activity:SetEnabled(search.category > 0)
    UpdateActivityHeader()
end

local function ResetDropdowns()
    search.category = 0
    wipe(search.activities)
    RefreshDropdowns()
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function BuildList()
    local s = B.scrollBox
    local scrollBox = CreateFrame("Frame", nil, tab, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", tab, "TOPLEFT", s.left, s.top)
    scrollBox:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", s.right - s.barWidth, s.bottom)
    local scrollBar = CreateFrame("EventFrame", nil, tab, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", s.barX, s.barTop)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 0, s.barBottom)
    P.scrollBox, P.scrollBar = scrollBox, scrollBar

    local view = CreateScrollBoxListTreeListView(0, 0, 0, 0, 0, 0)
    view:SetElementFactory(function(factory, node)
        local data = node:GetData()
        if data.dividerType then
            factory("LFGBrowseSearchEntryGroupingTemplate", function(row, rowNode)
                InitDivider(row, rowNode)
            end)
        elseif data.nested then
            factory("LFGBrowseNestedSearchEntryTemplate", function(row, rowNode)
                InitRow(row, rowNode:GetData())
            end)
        else
            factory("LFGBrowseSearchEntryTemplate", function(row, rowNode)
                InitRow(row, rowNode:GetData())
            end)
        end
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    local withBar = {
        CreateAnchor("TOPLEFT", s.left, s.top),
        CreateAnchor("BOTTOMRIGHT", s.right - s.barWidth, s.bottom),
    }
    local withoutBar = {
        withBar[1],
        CreateAnchor("BOTTOMRIGHT", s.right, s.bottom),
    }
    ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar, withBar, withoutBar)
end

local function BuildRefresh(anchor)
    local r = B.refresh
    local refresh = CreateFrame("Button", nil, tab)
    refresh:SetSize(r.size, r.size)
    refresh:SetPoint("LEFT", anchor, "RIGHT", r.gap, 0)
    refresh:SetNormalTexture("Interface\\Buttons\\UI-SquareButton-Up")
    refresh:SetPushedTexture("Interface\\Buttons\\UI-SquareButton-Down")
    refresh:SetDisabledTexture("Interface\\Buttons\\UI-SquareButton-Disabled")
    refresh:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local icon = refresh:CreateTexture(nil, "ARTWORK", nil, 5)
    icon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    icon:SetSize(r.icon, r.icon)
    icon:SetPoint("CENTER", refresh, "CENTER", r.iconX, 0)
    refresh:SetScript("OnMouseDown", function()
        icon:SetPoint("CENTER", refresh, "CENTER", r.pressedX, r.pressedY)
    end)
    refresh:SetScript("OnMouseUp", function()
        icon:SetPoint("CENTER", refresh, "CENTER", r.iconX, 0)
    end)
    refresh:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(LFG_LIST_SEARCH_AGAIN, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g,
            HIGHLIGHT_FONT_COLOR.b)
    end)
    refresh:SetScript("OnLeave", GameTooltip_Hide)
    refresh:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        DoSearch()
    end)
    P.refresh = refresh
end

local function OnTabShow()
    RefreshDropdowns()
    Rebuild()
end

function Browse.Build(parent)
    tab = UI.MakeTabFrame(parent)

    -- Blizzard anchors most of the tab to a hidden texture; this frame
    -- stands in for it and carries the inset's art
    local a = B.art
    local inset = CreateFrame("Frame", nil, tab)
    inset:SetPoint("TOPLEFT", tab, "TOPLEFT", a.topLeft[1], a.topLeft[2])
    inset:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", a.bottomRight[1], a.bottomRight[2])
    inset:SetFrameLevel(tab:GetFrameLevel())
    local insetBg = inset:CreateTexture(nil, "BACKGROUND")
    insetBg:SetAtlas("groupfinder-background")
    insetBg:SetPoint("TOPLEFT", inset, "TOPLEFT", B.insetBg, -B.insetBg)
    insetBg:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -B.insetBg, B.insetBg)
    local insetBorder = inset:CreateTexture(nil, "BORDER")
    insetBorder:SetAtlas("common-insideframe", true)
    insetBorder:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, B.insetBorderTop)
    insetBorder:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 0, 0)

    local stone = tab:CreateTexture(nil, "BACKGROUND", nil, -5)
    stone:SetAtlas("groupfinder-Stat-StoneBG")
    stone:SetPoint("TOPLEFT", tab, "TOPLEFT", B.stone.x, B.stone.y)
    stone:SetPoint("BOTTOMRIGHT", inset, "TOPRIGHT", 0, B.stone.bottom)

    local barTop = tab:CreateTexture(nil, "OVERLAY")
    barTop:SetAtlas("groupfinder-ScrollLine", true)
    barTop:SetPoint("LEFT", inset, "TOPLEFT", 0, B.barTop)
    barTop:SetPoint("RIGHT", inset, "TOPRIGHT", 0, B.barTop)
    local barMiddle = tab:CreateTexture(nil, "OVERLAY")
    barMiddle:SetAtlas("groupfinder-ScrollLine", true)
    barMiddle:SetPoint("LEFT", tab, "BOTTOMLEFT", 0, B.barMiddle)
    barMiddle:SetPoint("RIGHT", tab, "BOTTOMRIGHT", 0, B.barMiddle)

    local noResults = tab:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    noResults:SetWidth(B.noResults.width)
    noResults:SetPoint("TOP", inset, "TOP", 0, B.noResults.y)
    noResults:SetText(LFG_LIST_NO_RESULTS_FOUND)
    P.noResults = noResults

    local category = CreateFrame("DropdownButton", nil, tab, "WowStyle1DropdownTemplate")
    category:SetWidth(B.category.width)
    category:SetPoint("TOPLEFT", tab, "TOPLEFT", B.category.x, B.category.y)
    if category.SetDefaultText then category:SetDefaultText(CATEGORY) end
    P.category = category

    local activity = CreateFrame("DropdownButton", nil, tab, "WowStyle1DropdownTemplate")
    activity:SetWidth(B.activity.width)
    activity:SetPoint("LEFT", category, "RIGHT", B.activity.gap, 0)
    if activity.SetDefaultText then activity:SetDefaultText(LFGBROWSE_ACTIVITY_HEADER_DEFAULT) end
    P.activity = activity

    BuildRefresh(activity)

    local ok, options = pcall(CreateFrame, "DropdownButton", nil, tab, "LFGOptionsButton")
    if ok and options then
        options:SetPoint("TOPRIGHT", tab, "TOPRIGHT", B.options.x, B.options.y)
        options:SetupMenu(function(_, root)
            root:CreateCheckbox(LFG_LIST_IGNORE_SUGGESTED_LEVEL, Data.LevelFilterOff, function()
                Data.SetLevelFilterOff(not Data.LevelFilterOff())
            end)
        end)
    end

    BuildList()

    local spinner = CreateFrame("Frame", nil, tab, "LoadingSpinnerTemplate")
    spinner:SetPoint("CENTER", inset, "CENTER", 0, 0)
    spinner:SetFrameLevel(tab:GetFrameLevel() + 10)
    local label = spinner:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    label:SetText(SEARCHING)
    label:SetPoint("BOTTOM", spinner, "TOP", 0, 0)
    spinner:Hide()
    P.spinner = spinner

    local message = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    message:SetSize(B.message.width, B.message.height)
    message:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", B.message.x, B.message.y)
    message:SetText(SEND_MESSAGE)
    message:SetScript("OnClick", function()
        local info = Data.Result(selectedID)
        if info then ChatFrameUtil.SendTell(info.leaderName) end
    end)
    P.message = message

    local invite = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    invite:SetSize(B.invite.width, B.invite.height)
    invite:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", B.invite.x, B.invite.y)
    invite:SetText(GROUP_INVITE)
    invite:SetScript("OnClick", function()
        local info = Data.Result(selectedID)
        if info and Data.CanInviteResult(selectedID) then C_PartyInfo.InviteUnit(info.leaderName) end
    end)
    P.invite = invite

    tab:SetScript("OnShow", OnTabShow)
    tab:SetScript("OnHide", HideTooltip)
    return tab
end

--------------------------------------------------------------------------------
-- What the client says
--------------------------------------------------------------------------------

Data.Listen("search", function()
    if tab and tab:IsShown() then Render() end
end)

Data.Listen("results", function()
    if tab and tab:IsShown() then Rebuild() end
end)

-- A listing the player posted or edited: the filter follows it, as
-- Blizzard's does. Blizzard's hidden frame searches for a new one and the
-- spinner waits for that answer; an edit made from this window is searched
-- by nobody, since a search here needs a click, and the rows stay the last
-- search's until Refresh. Any change to the listing recolors the rows.
Data.Listen("entry", function(createdNew, wasPending)
    if not tab then return end
    if (createdNew or wasPending) and Data.HasEntry() then
        SelectEntryActivities()
        if createdNew then Data.ExpectSearch() end
    end
    RefreshDropdowns()
    if tab:IsShown() then Rebuild() end
end)

-- LFG_LIST_SHOW_SEARCH: Blizzard's frame sets its own filter and searches;
-- this window follows while it is up, or once it has taken the finder over.
-- A frame later, after the level filter's CVar event has reset the filter.
Data.Listen("showSearch", function(activityIDs)
    if not (UI:IsShown() or LFG.IsEnabled()) then return end
    Data.ExpectSearch()
    C_Timer.After(0, function()
        if activityIDs then SelectActivities(activityIDs) end
        if not UI:Open() then return end
        UI:SelectTab(2)
        RefreshDropdowns()
        Rebuild()
    end)
end)

Data.Listen("resultUpdated", function(resultID)
    if not (tab and tab:IsShown()) then return end
    ValidateSelection()
    ForEachResultRow(function(row)
        if row.resultID == resultID then UpdateRow(row) end
    end)
end)

Data.Listen("availability", RefreshDropdowns)
Data.Listen("filter", ResetDropdowns)
Data.Listen("group", UpdateButtons)

Data.Listen("lockdown", function()
    if tab and tab:IsShown() then Rebuild() end
end)

--------------------------------------------------------------------------------
-- Debug and registration
--------------------------------------------------------------------------------

function Browse.Dump(push)
    push("browse: category %s, activities checked %d, results %d of %d reported, selected %s",
        tostring(search.category), #search.activities, #results, total, tostring(selectedID))
    push("  searching: %s, failed: %s, tab built: %s, tooltip built: %s", tostring(Data.searching),
        tostring(Data.searchFailed), tostring(tab ~= nil), tostring(tooltip ~= nil))
    if tooltipError then push("  tooltip error: %s", tostring(tooltipError)) end
end

UI.RegisterTab(2, {
    build = Browse.Build,
    icon = "Interface\\ICONS\\INV_SideTab_GroupBrowsing_c60",
    tooltip = LFG_LIST_TAB_2,
})
