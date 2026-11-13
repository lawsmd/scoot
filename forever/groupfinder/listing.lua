--------------------------------------------------------------------------------
-- forever/groupfinder/listing.lua
-- The Listing tab: pick a category, check activities, set roles, write a
-- comment, post. A port of Blizzard's LFGListingFrame onto the window's own
-- frames and its own form.
--
-- The parts are made from Blizzard's templates where it has one (the role
-- buttons, the category buttons, the activity rows, the locked view's lines,
-- the inset) and from its atlases where it has none; the template scripts
-- that reach for Blizzard's own frame are replaced. The sizes and anchors are
-- LFG.LAYOUT.listing.
--
-- The form (the category, the checks, the playstyle, the voice mode, dirty)
-- is this file's table. Blizzard's hidden frame keeps a form of its own,
-- which follows the live listing and is never written from here.
--------------------------------------------------------------------------------

local addonName, addon = ...

local LFG = addon.ForeverGroupFinder
local Data = LFG.Data
local Host = LFG.Host
local UI = LFG.UI

local Listing = {}
LFG.Listing = Listing

local L = LFG.LAYOUT.listing

local VIEW_CATEGORIES, VIEW_ACTIVITIES, VIEW_LOCKED = 1, 2, 3
local ROW_GROUP, ROW_ACTIVITY = 1, 2

local CHECK_UP = "Interface\\Buttons\\UI-CheckBox-Up"
local CHECK_DOWN = "Interface\\Buttons\\UI-CheckBox-Down"
local CHECK_HIGHLIGHT = "Interface\\Buttons\\UI-CheckBox-Highlight"
local CHECK_MARK = "Interface\\Buttons\\UI-CheckBox-Check"
local CHECK_MARK_DISABLED = "Interface\\Buttons\\UI-CheckBox-Check-Disabled"
local MULTI_MARK = "Interface\\Buttons\\UI-MultiCheck-Up"
local MULTI_MARK_DISABLED = "Interface\\Buttons\\UI-MultiCheck-Disabled"

local form = {
    category = nil,
    activities = {},        -- activity id -> selected
    dirty = false,
    playstyle = nil,
    voiceMode = nil,
    commentRequired = false,
    view = VIEW_CATEGORIES,
}

local tab                   -- the tab's frame, nil until built
local P = {}                -- its parts by name
local inCategoryPick = false
local treeView

local function VoiceModes()
    return Enum.LFGEntryVoiceMode
end

--------------------------------------------------------------------------------
-- The form's activities
--------------------------------------------------------------------------------

local function CountSelected()
    local n = 0
    for _, on in pairs(form.activities) do
        if on then n = n + 1 end
    end
    return n
end

local function IsAnySelected()
    for _, on in pairs(form.activities) do
        if on then return true end
    end
    return false
end

local function IsAnyInGroupSelected(groupID)
    for id, on in pairs(form.activities) do
        if on and Data.ActivityGroup(id) == groupID then return true end
    end
    return false
end

local function AreAllInGroupSelected(groupID)
    for id, on in pairs(form.activities) do
        if not on and Data.ActivityGroup(id) == groupID then return false end
    end
    return true
end

local UpdatePostButton

local function SetDirty(state)
    form.dirty = state and true or false
    if tab then UpdatePostButton() end
end

-- allowCreate lets an id into the form that the category's list did not
-- give it; a click from the player marks the form changed
local function SetActivity(activityID, on, allowCreate, userInput)
    if not allowCreate and form.activities[activityID] == nil then return end
    form.activities[activityID] = on and true or false
    if tab then UpdatePostButton() end
    if userInput then
        if Data.HasEntry() then
            SetDirty(true)
        else
            SetDirty(IsAnySelected())
        end
    end
end

local function SetAllActivities(on, userInput)
    for id in pairs(form.activities) do
        SetActivity(id, on, false, userInput)
    end
end

local function SetAllInGroup(groupID, on, userInput)
    for id in pairs(form.activities) do
        if Data.ActivityGroup(id) == groupID then
            SetActivity(id, on, false, userInput)
        end
    end
end

-- The category's activities, each off; then the live listing's on, or all of
-- them on in a category that chooses for the player
local function UpdateActivities()
    form.activities = {}
    if not form.category then return end
    for _, id in ipairs(Data.FilteredActivities(form.category)) do
        SetActivity(id, false, true)
    end
    local entry = Data.Entry()
    if entry then
        for _, id in ipairs(entry.activityIDs) do
            SetActivity(id, true)
        end
    else
        local info = Data.CategoryInfo(form.category)
        if info and info.autoChooseActivity then
            SetAllActivities(true)
        end
    end
end

--------------------------------------------------------------------------------
-- Buttons' state
--------------------------------------------------------------------------------

local function CanPostWithComment()
    if not form.commentRequired then return true end
    return Host.CommentText() ~= ""
end

-- Blizzard's rules for Post, in Blizzard's order. A rule that has a reason
-- gives it to the button's tooltip.
UpdatePostButton = function()
    local post = P.post
    if not post then return end
    local function off(reason)
        post.errorText = reason
        post:SetEnabled(false)
    end
    if not Data.CanEdit() then
        return off(Data.HasEntry() and LFG_LIST_ONLY_LEADER_UPDATE or LFG_LIST_ONLY_LEADER_CREATE)
    end
    if CountSelected() > Data.MaxActivities() then
        return off(LFG_LIST_TOO_MANY_ACTIVITIES_SELECTED)
    end
    if not form.playstyle then
        return off(GROUP_FINDER_PLAYSTYLE_REQUIRED)
    end
    if not form.dirty or (not Data.HasEntry() and not IsAnySelected()) then
        return off(nil)
    end
    if not CanPostWithComment() then
        return off(nil)
    end
    if Data.InHomeGroup() then
        local count = GetNumGroupMembers(LE_PARTY_CATEGORY_HOME)
        local hasSpace, least = true, 0
        for id, on in pairs(form.activities) do
            if on then
                local info = Data.ActivityInfo(id)
                local max = info and info.maxNumPlayers or 0
                if max ~= 0 then
                    if max <= count then hasSpace = false end
                    if max < least or least == 0 then least = max end
                end
            end
        end
        if not hasSpace then
            return off(string.format(LFG_LIST_TOO_MANY_FOR_ACTIVITY, least))
        end
    end
    post.errorText = nil
    post:SetEnabled(true)
end

local function UpdateButtonText()
    if not tab then return end
    if Data.HasEntry() then
        P.post:SetText(LFG_POST_GROUP_UPDATE)
        P.back:SetText(LFG_LIST_UNLIST)
    else
        P.post:SetText(Data.InHomeGroup() and LFG_POST_GROUP_PARTY or LFG_POST_GROUP_SOLO)
        P.back:SetText(BACK)
    end
end

--------------------------------------------------------------------------------
-- Roles
--------------------------------------------------------------------------------

local function SoloRoles()
    return {
        tank = P.solo.TANK.CheckButton:GetChecked(),
        healer = P.solo.HEALER.CheckButton:GetChecked(),
        dps = P.solo.DAMAGER.CheckButton:GetChecked(),
    }
end

local function LoadSoloRoles()
    if not tab then return end
    local roles = Data.Roles()
    P.solo.TANK.CheckButton:SetChecked(roles.tank and true or false)
    P.solo.HEALER.CheckButton:SetChecked(roles.healer and true or false)
    P.solo.DAMAGER.CheckButton:SetChecked(roles.dps and true or false)
end

local function UpdateGroupRole()
    if not tab then return end
    local icon = P.groupRoleIcon
    local role = UnitGroupRolesAssigned("player")
    if role == "NONE" or not role then
        icon:Hide()
    else
        icon:Show()
        icon.roleID = role
        if GetTexCoordsForRole and icon:GetNormalTexture() then
            icon:GetNormalTexture():SetTexCoord(GetTexCoordsForRole(role))
        end
        if GetBackgroundTexCoordsForRole and icon.Background then
            icon.Background:SetTexCoord(GetBackgroundTexCoordsForRole(role))
        end
    end
    if P.roleDropdown.GenerateMenu then P.roleDropdown:GenerateMenu() end
    P.rolePoll:SetEnabled(Data.CanPollRoles())
end

--------------------------------------------------------------------------------
-- The category view
--------------------------------------------------------------------------------

local SetCategory

local function RefreshCategories()
    local view = P.categoryView
    local buttons = view.buttons
    local categories = Data.Categories()
    for i, category in ipairs(categories) do
        local button = buttons[i]
        if not button then
            button = CreateFrame("Button", nil, view, "LFGListingCategoryTemplate")
            if i == 1 then
                button:SetPoint("TOP", view, "TOP", 0, L.categoryView.first)
            else
                button:SetPoint("TOP", buttons[i - 1], "BOTTOM", 0, L.categoryView.gap)
            end
            -- The template's click sets Blizzard's own form
            button:SetScript("OnClick", function(self)
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                SetCategory(self.categoryID)
            end)
            buttons[i] = button
        end
        button:SetText(category.name)
        button.categoryID = category.id
        if button.Icon then button.Icon:SetAtlas(category.icon) end
        button:Show()
    end
    for i = #categories + 1, #buttons do
        buttons[i]:Hide()
    end
end

--------------------------------------------------------------------------------
-- The activity tree
--------------------------------------------------------------------------------

local function SetCheckMark(check, multi)
    check:SetCheckedTexture(multi and MULTI_MARK or CHECK_MARK)
    check:SetDisabledCheckedTexture(multi and MULTI_MARK_DISABLED or CHECK_MARK_DISABLED)
end

local function InitGroupRow(row, data, collapsed)
    if not row then return end
    row.ExpandOrCollapseButton:SetShown(data.showExpand)
    row.CheckButton:SetPoint("LEFT", row.ExpandOrCollapseButton, data.showExpand and "RIGHT" or "LEFT", 4, 0)
    row.ExpandOrCollapseButton:SetNormalTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up"
        or "Interface\\Buttons\\UI-MinusButton-Up")

    local all = AreAllInGroupSelected(data.groupID)
    local any = IsAnyInGroupSelected(data.groupID)
    row.CheckButton:SetChecked(all or any)
    SetCheckMark(row.CheckButton, any and not all)

    local name = row.NameButton.Name
    name:SetWidth(0)
    name:SetText(data.name)
    name:SetFontObject(_G["LFGActivityHeader"] or GameFontNormal)
    row.NameButton:SetWidth(name:GetWidth())

    row.InstanceLockWarningIcon:Hide()
    row.Level:Hide()
end

local function InitActivityRow(row, data)
    if not row then return end
    row.ExpandOrCollapseButton:Hide()
    row.CheckButton:SetPoint("LEFT", row.ExpandOrCollapseButton, "RIGHT", 4, 0)
    row.CheckButton:SetChecked(form.activities[data.activityID] and true or false)
    SetCheckMark(row.CheckButton, false)

    local level = UnitLevel("player")
    local font = _G["LFGActivityEntry"] or GameFontNormal
    if data.maxLevel ~= 0 and data.maxLevel < level then
        font = _G["LFGActivityEntryTrivial"] or font
    elseif data.minLevel ~= 0 and data.minLevel > level then
        font = _G["LFGActivityEntryDifficult"] or font
    end
    local name = row.NameButton.Name
    name:SetWidth(0)
    name:SetText(data.name)
    name:SetFontObject(font)
    row.Level:SetFontObject(font)
    row.NameButton:SetWidth(name:GetWidth())

    local warning = row.InstanceLockWarningIcon
    local completed, total = Data.LockFor(data.activityID)
    if completed then
        warning.encountersCompleted = completed
        warning.encountersTotal = total
        warning:Show()
    else
        warning:Hide()
    end

    row.Level:Show()
    if data.minLevel == data.maxLevel or data.maxLevel == 0 then
        if data.minLevel == 0 then
            row.Level:SetText("")
        else
            row.Level:SetText(string.format(LFD_LEVEL_FORMAT_SINGLE, data.minLevel))
        end
    else
        row.Level:SetText(string.format(LFD_LEVEL_FORMAT_RANGE, data.minLevel, data.maxLevel))
    end
end

local function BuildTreeView(scrollBox, scrollBar)
    local view = CreateScrollBoxListTreeListView(0)
    view:SetElementFactory(function(factory, node)
        local data = node:GetData()
        if data.rowType == ROW_GROUP then
            factory("LFGListingActivityRowTemplate", function(row)
                InitGroupRow(row, data, node:IsCollapsed())
                row.CheckButton:SetScript("OnClick", function(button)
                    local rowNode = button:GetParent():GetElementData()
                    local group = rowNode:GetData()
                    SetAllInGroup(group.groupID, not IsAnyInGroupSelected(group.groupID), true)
                    InitGroupRow(view:FindFrame(rowNode), group, rowNode:IsCollapsed())
                    for _, child in ipairs(rowNode.nodes) do
                        local childRow = view:FindFrame(child)
                        if childRow then InitActivityRow(childRow, child:GetData()) end
                    end
                end)
                row.ExpandOrCollapseButton:SetScript("OnClick", function(button)
                    local rowNode = button:GetParent():GetElementData()
                    rowNode:ToggleCollapsed(true)
                    InitGroupRow(view:FindFrame(rowNode), rowNode:GetData(), rowNode:IsCollapsed())
                end)
            end)
        else
            factory("LFGListingActivityRowTemplate", function(row)
                InitActivityRow(row, data)
                row.CheckButton:SetScript("OnClick", function(button)
                    local rowNode = button:GetParent():GetElementData()
                    local id = rowNode:GetData().activityID
                    SetActivity(id, not form.activities[id], false, true)
                    local parent = rowNode.parent
                    local parentRow = parent and view:FindFrame(parent)
                    if parentRow then
                        InitGroupRow(parentRow, parent:GetData(), parent:IsCollapsed())
                    end
                end)
            end)
        end
    end)
    local s = L.scrollBox
    view:SetPadding(s.padding, s.padding, s.padding, s.padding, 0)
    view:SetElementExtent(s.rowHeight)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    local bottom = s.bottomBase + (VoiceModes() and L.voiceRow or 0)
    local withBar = {
        CreateAnchor("TOPLEFT", 0, s.top),
        CreateAnchor("BOTTOMRIGHT", s.barInset, bottom),
    }
    local withoutBar = {
        withBar[1],
        CreateAnchor("BOTTOMRIGHT", 0, bottom),
    }
    ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar, withBar, withoutBar)
    return view
end

local function ActivityNodeBefore(a, b)
    return Data.ActivityBefore(a:GetData(), b:GetData())
end

-- Activities in no group stand above the groups; groups by their order
-- index, then by name
local function TopNodeBefore(a, b)
    local l, r = a:GetData(), b:GetData()
    if l.rowType ~= r.rowType then return l.rowType > r.rowType end
    if l.orderIndex ~= r.orderIndex then return l.orderIndex < r.orderIndex end
    if l.rowType == ROW_ACTIVITY then return Data.ActivityBefore(l, r) end
    return strcmputf8i(l.name, r.name) < 0
end

local function RefreshTree()
    if not (tab and form.category) then return end
    P.levelCheck:SetChecked(Data.LevelFilterOff())
    local tree = Data.ActivityTree(form.category)
    local provider = CreateTreeDataProvider()
    for _, row in ipairs(tree.loose) do
        row.rowType = ROW_ACTIVITY
        provider:Insert(row)
    end
    local level = UnitLevel("player")
    for _, group in ipairs(tree.groups) do
        local node = provider:Insert({
            rowType = ROW_GROUP,
            groupID = group.groupID,
            name = group.name,
            orderIndex = group.orderIndex,
            showExpand = tree.multi,
        })
        for _, row in ipairs(group.activities) do
            row.rowType = ROW_ACTIVITY
            node:Insert(row)
        end
        if level and not group.suggested and tree.multi then
            node:SetCollapsed(true)
        end
        node:SetSortComparator(ActivityNodeBefore)
    end
    provider:SetSortComparator(TopNodeBefore)
    P.scrollBox:SetDataProvider(provider)
end

--------------------------------------------------------------------------------
-- The activity view
--------------------------------------------------------------------------------

local function OnCommentTyped()
    SetDirty(true)
end

-- What Blizzard's activity view does as it shows: the list or the comment
-- alone, the comment box in place, the dropdowns, the tree
local function ShowActivityView()
    if not (tab and form.category) then return end
    local view = P.activityView
    local info = Data.CategoryInfo(form.category)
    local secured = C_LFGList.IsPlayerAuthenticatedForLFG(form.category) and true or false
    local holder = P.commentHolder
    local c = L.comment
    local voiceRow = VoiceModes() and L.voiceRow or 0

    holder:ClearAllPoints()
    if info and info.autoChooseActivity then
        P.barMiddle:Hide()
        P.scrollBox:Hide()
        P.scrollBar:Hide()
        form.commentRequired = true
        holder:SetPoint("CENTER", view, "CENTER", 0, c.requiredY)
        holder:SetHeight(c.requiredHeight)
    else
        P.barMiddle:Show()
        P.scrollBox:Show()
        form.commentRequired = false
        holder:SetPoint("BOTTOM", view, "BOTTOM", 0, c.bottom + voiceRow)
        holder:SetHeight(c.height)
    end

    Host.TakeComment(holder, OnCommentTyped)
    Host.ClearCommentFocus()
    local line = secured and (form.commentRequired and DESCRIPTION_OF_YOUR_GROUP_MANDATORY
        or DESCRIPTION_OF_YOUR_GROUP) or LFG_AUTHENTICATOR_DESCRIPTION_BOX
    Host.SetCommentState(line, secured)
    if form.commentRequired and inCategoryPick then
        Host.FocusComment()
    end

    if P.playstyle.SetDefaultText then
        P.playstyle:SetDefaultText(DISABLED_FONT_COLOR:WrapTextInColorCode(GROUP_FINDER_PLAYSTYLE_REQUIRED))
    end
    if P.playstyle.GenerateMenu then P.playstyle:GenerateMenu() end
    if P.voice and P.voice.GenerateMenu then P.voice:GenerateMenu() end
    RefreshTree()
    UpdatePostButton()
end

--------------------------------------------------------------------------------
-- The locked view: a group member who is not the leader
--------------------------------------------------------------------------------

local function RefreshLocked()
    if not tab then return end
    local view = P.lockedView
    local lines = view.lines
    for _, line in ipairs(lines) do line:Hide() end

    local entry = Data.Entry()
    if not entry then
        view.ErrorText:SetText(LFG_LIST_ONLY_LEADER_CREATE)
        view.ActivityText:Hide()
        return
    end
    view.ErrorText:SetText(LFG_LIST_ONLY_LEADER_UPDATE)
    view.ActivityText:Show()

    local byGroup, groupIDs = Data.ActivitiesByGroup(entry.activityIDs)
    local verboseCount = 0
    for _, groupID in ipairs(groupIDs) do
        if groupID ~= 0 then verboseCount = verboseCount + 1 end
        verboseCount = verboseCount + #byGroup[groupID]
    end
    local verbose = verboseCount <= L.locked.maxLines

    local used = 0
    local function add(text, tooltip)
        if used >= L.locked.maxLines then return false end
        used = used + 1
        local line = lines[used]
        if not line then
            line = CreateFrame("Frame", nil, view, "LFGListingLockedViewActivityTemplate")
            lines[used] = line
        end
        line:ClearAllPoints()
        if used == 1 then
            line:SetPoint("TOPLEFT", view.ActivityText, "BOTTOMLEFT", L.locked.lineX, L.locked.lineY)
        else
            line:SetPoint("TOPLEFT", lines[used - 1], "BOTTOMLEFT", 0, L.locked.lineGap)
        end
        line.Text:SetSize(0, 0)
        line.Text:SetText(text)
        line.tooltip = tooltip
        line:SetSize(line.Text:GetWidth(), line.Text:GetHeight())
        line:Show()
        return true
    end
    local function count(n)
        return HIGHLIGHT_FONT_COLOR:WrapTextInColorCode("(" .. string.format(LFGBROWSE_ACTIVITY_COUNT, n) .. ")")
    end

    for _, groupID in ipairs(groupIDs) do
        local ids = byGroup[groupID]
        if groupID == 0 then
            for _, id in ipairs(ids) do
                if not add(Data.ActivityName(Data.ActivityInfo(id))) then return end
            end
        else
            local groupName = C_LFGList.GetActivityGroupInfo(groupID) or ""
            if verbose then
                if not add(groupName .. " " .. count(#ids)) then return end
                for _, id in ipairs(ids) do
                    local name = Data.ActivityName(Data.ActivityInfo(id))
                    if not add(string.format(LFG_LIST_INDENT, name)) then return end
                end
            else
                local tooltip = groupName
                for _, id in ipairs(ids) do
                    local name = Data.ActivityName(Data.ActivityInfo(id))
                    tooltip = tooltip .. "\n" .. string.format(LFG_LIST_INDENT, name)
                end
                if not add(groupName .. " " .. count(#ids), tooltip) then return end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The view: categories, activities, or locked
--------------------------------------------------------------------------------

local function UpdateView()
    if not tab then return end
    if not Data.CanEdit() then
        form.view = VIEW_LOCKED
    elseif not form.category then
        form.view = VIEW_CATEGORIES
    else
        form.view = VIEW_ACTIVITIES
    end
    P.categoryView:SetShown(form.view == VIEW_CATEGORIES)
    P.activityView:SetShown(form.view == VIEW_ACTIVITIES)
    P.lockedView:SetShown(form.view == VIEW_LOCKED)
    if form.view == VIEW_CATEGORIES then
        RefreshCategories()
    elseif form.view == VIEW_LOCKED then
        RefreshLocked()
    end

    local grouped = Data.InHomeGroup()
    P.soloRoles:SetShown(not grouped)
    P.groupRoles:SetShown(grouped)

    UpdatePostButton()
    P.back:SetEnabled(form.view == VIEW_ACTIVITIES)
    P.newPlayerCheck:SetEnabled(Data.CanEdit())
end

SetCategory = function(categoryID)
    inCategoryPick = true
    local wasUp = tab ~= nil and P.activityView:IsVisible()
    form.category = categoryID
    UpdateActivities()
    UpdateView()
    -- A view already up does not show again; its content is redone here
    if wasUp and form.view == VIEW_ACTIVITIES then
        ShowActivityView()
    end
    inCategoryPick = false
end

local function ClearCategory()
    form.category = nil
    UpdateActivities()
    UpdateView()
end

local function ClearForm()
    ClearCategory()
    Host.ClearComment()
    Host.ClearCommentFocus()
    local modes = VoiceModes()
    form.voiceMode = modes and modes.None or nil
    SetDirty(false)
end

-- The live listing into the form: its category and activities, the comment
-- (the client fills Blizzard's box), the three options
local function LoadEntry()
    local entry = Data.Entry()
    if not entry then return end
    local info = Data.ActivityInfo(entry.activityIDs[1])
    if not info then return end
    SetCategory(info.categoryID)
    Host.LoadComment()
    local modes = VoiceModes()
    form.voiceMode = entry.voiceMode or (modes and modes.None) or nil
    -- Blizzard's form never reads the listing's playstyle back, which leaves
    -- its Post off after a reload until one is picked again
    if entry.generalPlaystyle and entry.generalPlaystyle ~= 0 then
        form.playstyle = entry.generalPlaystyle
    end
    if tab then
        P.newPlayerCheck:SetChecked(entry.newPlayerFriendly and true or false)
        if P.playstyle.GenerateMenu then P.playstyle:GenerateMenu() end
        if P.voice and P.voice.GenerateMenu then P.voice:GenerateMenu() end
    end
    SetDirty(false)
end

--------------------------------------------------------------------------------
-- Post and Back
--------------------------------------------------------------------------------

-- One restricted call for the click: an update, a removal or a creation
local function OnPostClick()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if not form.dirty then return end
    local ids = {}
    for id, on in pairs(form.activities) do
        if on then ids[#ids + 1] = id end
    end
    local any = #ids > 0
    local newPlayerFriendly = P.newPlayerCheck:GetChecked() and true or false
    if any then Data.MatchVoiceProvider(form.voiceMode) end

    local listed = Data.HasEntry()
    if listed and any then
        Data.UpdateListing(ids, newPlayerFriendly, form.playstyle, form.voiceMode)
    elseif listed then
        Data.RemoveListing()
    elseif any then
        Data.CreateListing(ids, newPlayerFriendly, form.playstyle, form.voiceMode)
    else
        return
    end
    if any then Data.SetRoles(SoloRoles()) end
end

local function OnBackClick()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if Data.HasEntry() then
        Data.RemoveListing()
    else
        ClearForm()
    end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function MakeCheck(parent, size)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(size, size)
    check:SetNormalTexture(CHECK_UP)
    check:SetPushedTexture(CHECK_DOWN)
    check:SetHighlightTexture(CHECK_HIGHLIGHT, "ADD")
    check:SetCheckedTexture(CHECK_MARK)
    check:SetDisabledCheckedTexture(CHECK_MARK_DISABLED)
    return check
end

local function CheckSound(check)
    PlaySound(check:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
end

local ROLE_ATLAS = { TANK = "UI-LFG-RoleIcon-Tank", HEALER = "UI-LFG-RoleIcon-Healer", DAMAGER = "UI-LFG-RoleIcon-DPS" }
local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }

local function BuildSoloRoles()
    local s = L.soloRoles
    local holder = CreateFrame("Frame", nil, tab)
    holder:SetSize(s.width, s.height)
    holder:SetPoint("TOPLEFT", tab, "TOPLEFT", s.x, s.y)
    P.soloRoles = holder
    P.solo = {}
    local classRoles = Data.ClassRoles()
    local previous
    for _, role in ipairs(ROLE_ORDER) do
        local button = CreateFrame("Button", nil, holder, "LFGListingRoleButtonTemplate")
        button.roleID = role
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", s.gap, 0)
        else
            button:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        end
        local normal = button:GetNormalTexture()
        if normal then
            normal:ClearAllPoints()
            normal:SetPoint("CENTER")
            normal:SetTexCoord(0, 1, 0, 1)
            normal:SetAtlas(ROLE_ATLAS[role], true)
        end
        if button.Background then button.Background:SetAtlas(ROLE_ATLAS[role] .. "-Background", true) end
        if button.cover then button.cover:SetShown(not classRoles[role]) end
        -- The template's click saves the roles of Blizzard's own buttons
        button.CheckButton:SetScript("OnClick", function(self)
            CheckSound(self)
            if not Data.SetRoles(SoloRoles()) then
                self:SetChecked(not self:GetChecked())
            end
        end)
        P.solo[role] = button
        previous = button
    end
end

local function BuildGroupRoles()
    local g = L.groupRoles
    local holder = CreateFrame("Frame", nil, tab)
    holder:SetSize(g.width, g.height)
    holder:SetPoint("TOPLEFT", tab, "TOPLEFT", g.x, g.y)
    holder:Hide()
    P.groupRoles = holder

    local icon = CreateFrame("Button", nil, holder, "LFGListingRoleTemplate")
    icon:SetPoint("TOPRIGHT", holder, "TOPRIGHT", L.groupRoleIcon.x, L.groupRoleIcon.y)
    if icon.Background then icon.Background:SetAlpha(L.groupRoleIcon.backgroundAlpha) end
    P.groupRoleIcon = icon

    local poll = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    poll:SetSize(L.rolePoll.width, L.rolePoll.height)
    poll:SetPoint("TOPLEFT", holder, "TOPLEFT", L.rolePoll.x, L.rolePoll.y)
    poll:SetText(ROLE_POLL)
    poll:SetMotionScriptsWhileDisabled(true)
    poll:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        InitiateRolePoll()
    end)
    poll:SetScript("OnEnter", function(self)
        if self:IsEnabled() then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ERR_LFG_ROLE_CHECK_ONLY_LEADER, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    poll:SetScript("OnLeave", GameTooltip_Hide)
    P.rolePoll = poll

    local dropdown = CreateFrame("DropdownButton", nil, holder, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOP", poll, "BOTTOM", 0, L.roleDropdown.y)
    dropdown:SetWidth(L.roleDropdown.width)
    dropdown:SetupMenu(function(_, root)
        local function isSelected(value) return UnitGroupRolesAssigned("player") == value end
        local function setSelected(value) UnitSetRole("player", value) end
        root:CreateRadio(TANK, isSelected, setSelected, "TANK")
        root:CreateRadio(HEALER, isSelected, setSelected, "HEALER")
        root:CreateRadio(DAMAGER, isSelected, setSelected, "DAMAGER")
    end)
    dropdown:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(SELECT_YOUR_ROLE)
        GameTooltip:Show()
    end)
    dropdown:HookScript("OnLeave", GameTooltip_Hide)
    P.roleDropdown = dropdown
end

local function BuildNewPlayerFriendly()
    local n = L.newPlayer
    local button = CreateFrame("Button", nil, tab)
    button:SetSize(n.size, n.size)
    button:SetPoint("TOPRIGHT", tab, "TOPRIGHT", n.x, n.y)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetNormalAtlas("UI-LFG-RoleIcon-Leader")
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetAtlas("newplayerchat-chaticon-newcomer")
    overlay:SetSize(n.overlay, n.overlay)
    overlay:SetPoint("TOPRIGHT", button, "TOPRIGHT", n.overlayX, n.overlayY)

    local check = MakeCheck(button, n.check)
    check:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", n.checkX, n.checkY)
    check:SetScript("OnShow", function(self)
        if not Data.HasEntry() then self:SetChecked(Data.NewPlayerFriendlyDefault()) end
    end)
    check:SetScript("OnClick", function(self)
        CheckSound(self)
        Data.SetNewPlayerFriendlyDefault(self:GetChecked())
        SetDirty(true)
    end)
    button:SetScript("OnEnter", function(self)
        if check:IsEnabled() then check:LockHighlight() end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(LFG_LIST_NEW_PLAYER_FRIENDLY_TOOLTIP, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        check:UnlockHighlight()
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function()
        if check:IsEnabled() then check:Click() end
    end)
    P.newPlayerCheck = check
end

local function BuildActivityView()
    local a = L.activityView
    local view = CreateFrame("Frame", nil, tab)
    view:SetPoint("TOPLEFT", tab, "TOPLEFT", a.topLeft[1], a.topLeft[2])
    view:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", a.bottomRight[1], a.bottomRight[2])
    view:Hide()
    P.activityView = view

    local barTop = view:CreateTexture(nil, "OVERLAY")
    barTop:SetAtlas("groupfinder-ScrollLine", true)
    barTop:SetPoint("LEFT", view, "TOPLEFT", 0, L.barTop)
    barTop:SetPoint("RIGHT", view, "TOPRIGHT", 0, L.barTop)
    local barMiddle = view:CreateTexture(nil, "OVERLAY")
    barMiddle:SetAtlas("groupfinder-ScrollLine", true)
    barMiddle:SetPoint("LEFT", view, "BOTTOMLEFT", 0, L.barMiddle)
    barMiddle:SetPoint("RIGHT", view, "BOTTOMRIGHT", 0, L.barMiddle)
    P.barMiddle = barMiddle

    local p = L.playstyle
    local playstyle = CreateFrame("DropdownButton", nil, view, "WowStyle1DropdownTemplate")
    playstyle:SetSize(p.width, p.height)
    playstyle:SetPoint("TOPLEFT", view, "TOPLEFT", p.x, p.y)
    playstyle:SetupMenu(function(_, root)
        local styles = Enum.LFGEntryGeneralPlaystyle
        if not styles then return end
        local function isSelected(value) return form.playstyle == value end
        local function setSelected(value)
            form.playstyle = value
            UpdatePostButton()
        end
        for _, key in ipairs({ "Learning", "FunRelaxed", "FunSerious", "Expert" }) do
            local value = styles[key]
            if value then
                local label = GetGeneralPlaystyleString and GetGeneralPlaystyleString(value) or key
                root:CreateRadio(label, isSelected, setSelected, value)
            end
        end
    end)
    P.playstyle = playstyle

    local lc = L.levelCheck
    local levelText = view:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    levelText:SetSize(lc.textWidth, lc.textHeight)
    levelText:SetJustifyH("RIGHT")
    levelText:SetJustifyV("MIDDLE")
    levelText:SetWordWrap(true)
    levelText:SetMaxLines(2)
    levelText:SetText(LFG_LIST_IGNORE_SUGGESTED_LEVEL)
    levelText:SetPoint("TOPRIGHT", view, "TOPRIGHT", lc.x, lc.y)
    local levelCheck = CreateFrame("CheckButton", nil, view, "UICheckButtonTemplate")
    levelCheck:SetSize(lc.size, lc.size)
    levelCheck:SetPoint("LEFT", levelText, "RIGHT", lc.gapX, lc.gapY)
    levelCheck:SetScript("OnClick", function(self)
        Data.SetLevelFilterOff(self:GetChecked())
    end)
    P.levelCheck = levelCheck

    local s = L.scrollBox
    local scrollBox = CreateFrame("Frame", nil, view, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", view, "TOPLEFT", 0, s.top)
    scrollBox:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", s.barInset, s.bottomBase + (VoiceModes() and L.voiceRow or 0))
    local scrollBar = CreateFrame("EventFrame", nil, view, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", s.barX, s.barTop)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", s.barX, s.barBottom)
    P.scrollBox, P.scrollBar = scrollBox, scrollBar
    treeView = BuildTreeView(scrollBox, scrollBar)

    local holder = CreateFrame("Frame", nil, view)
    holder:SetSize(L.comment.width, L.comment.height)
    holder:SetPoint("BOTTOM", view, "BOTTOM", 0, L.comment.bottom)
    P.commentHolder = holder

    local modes = VoiceModes()
    if modes then
        form.voiceMode = form.voiceMode or modes.None
        local v = L.voice
        local voice = CreateFrame("DropdownButton", nil, view, "WowStyle1DropdownTemplate")
        voice:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", v.x, v.y)
        voice:SetWidth(v.width)
        local labels = {
            [modes.None] = VOICE_CHAT_MODE_NONE,
            [modes.Legacy] = VOICE_CHAT_MODE_LEGACY,
            [modes.Discord] = VOICE_CHAT_MODE_DISCORD,
            [modes.Custom] = VOICE_CHAT_MODE_CUSTOM,
        }
        voice:SetupMenu(function(_, root)
            local function isSelected(value) return form.voiceMode == value end
            local function setSelected(value)
                form.voiceMode = value
                SetDirty(true)
            end
            local discord = C_Discord and C_Discord.IsVoiceEnabled and C_Discord.IsVoiceEnabled()
            for _, key in ipairs({ "None", "Discord", "Legacy", "Custom" }) do
                local value = modes[key]
                if value ~= nil and labels[value] and (key ~= "Discord" or discord) then
                    root:CreateRadio(labels[value], isSelected, setSelected, value)
                end
            end
        end)
        local label = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetJustifyH("RIGHT")
        label:SetText(VOICE_CHAT)
        label:SetPoint("RIGHT", voice, "LEFT", v.labelGap, 0)
        P.voice = voice
    end

    view:SetScript("OnShow", ShowActivityView)
    view:SetScript("OnHide", function() Host.ReleaseComment() end)
end

local function BuildLockedView()
    local k = L.locked
    local view = CreateFrame("Frame", nil, tab)
    view:SetSize(k.width, k.height)
    view:SetPoint("TOPLEFT", tab, "TOPLEFT", k.x, k.y)
    view:Hide()
    view.lines = {}
    local errorText = view:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    errorText:SetWidth(k.textWidth)
    errorText:SetJustifyH("LEFT")
    errorText:SetPoint("TOPLEFT", view, "TOPLEFT", k.errorX, k.errorY)
    errorText:SetText(LFG_LIST_ONLY_LEADER_CREATE)
    local activityText = view:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    activityText:SetWidth(k.textWidth)
    activityText:SetJustifyH("LEFT")
    activityText:SetPoint("TOPLEFT", errorText, "BOTTOMLEFT", 0, k.activityY)
    activityText:SetText(LFG_LIST_MY_ACTIVITY_LIST_HEADER)
    view.ErrorText, view.ActivityText = errorText, activityText
    P.lockedView = view
end

local function OnTabShow()
    if Data.HasEntry() then
        LoadEntry()
        LoadSoloRoles()
    else
        LoadSoloRoles()
        if not form.dirty then
            form.voiceMode = Data.DefaultVoiceMode()
            if P.voice and P.voice.GenerateMenu then P.voice:GenerateMenu() end
        end
        SetDirty(IsAnySelected())
    end
    Data.RequestLocks()
    UpdateButtonText()
    UpdateView()
    UpdateGroupRole()
end

function Listing.Build(parent)
    tab = UI.MakeTabFrame(parent)

    local r = L.roles
    local roles = tab:CreateTexture(nil, "BACKGROUND")
    roles:SetAtlas("groupfinder-roles-background")
    roles:SetPoint("TOPLEFT", tab, "TOPLEFT", r.topLeft[1], r.topLeft[2])
    roles:SetPoint("BOTTOMRIGHT", tab, "TOPRIGHT", r.bottomRight[1], r.bottomRight[2])

    local inset = CreateFrame("Frame", nil, tab, "LFGListingInsetTemplate")
    if inset.Bg then inset.Bg:Hide() end

    -- A line across the inset's top: Blizzard's vertical divider art turned
    -- a quarter
    local divider = CreateFrame("Frame", nil, tab)
    divider:SetSize(L.divider.width, L.divider.height)
    divider:SetPoint("TOP", inset, "TOP", 0, 0)
    divider:SetFrameLevel(tab:GetFrameLevel() + 20)
    local line = divider:CreateTexture(nil, "OVERLAY")
    line:SetAtlas("common-framedivider")
    line:SetSize(L.divider.width, L.divider.height)
    line:SetPoint("CENTER", divider, "TOP", 0, 0)
    line:SetRotation(math.rad(90))

    local back = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    back:SetSize(L.back.width, L.back.height)
    back:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", L.back.x, L.back.y)
    back:SetScript("OnClick", OnBackClick)
    -- Blizzard's two buttons sit at frame level 4, above the inset, whose
    -- art otherwise draws over theirs and leaves the text alone
    back:SetFrameLevel(tab:GetFrameLevel() + L.buttonLevel)
    P.back = back

    local post = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    post:SetSize(L.post.width, L.post.height)
    post:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", L.post.x, L.post.y)
    post:SetMotionScriptsWhileDisabled(true)
    post:SetFrameLevel(tab:GetFrameLevel() + L.buttonLevel)
    post:SetScript("OnClick", OnPostClick)
    post:SetScript("OnEnter", function(self)
        if not self.errorText then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.errorText, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    post:SetScript("OnLeave", GameTooltip_Hide)
    P.post = post

    BuildSoloRoles()
    BuildGroupRoles()
    BuildNewPlayerFriendly()

    local cv = L.categoryView
    local categoryView = CreateFrame("Frame", nil, tab)
    categoryView:SetPoint("TOPLEFT", tab, "TOPLEFT", cv.topLeft[1], cv.topLeft[2])
    categoryView:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", cv.bottomRight[1], cv.bottomRight[2])
    categoryView.buttons = {}
    P.categoryView = categoryView

    BuildActivityView()
    BuildLockedView()

    tab:SetScript("OnShow", OnTabShow)
    return tab
end

--------------------------------------------------------------------------------
-- What the client says
--------------------------------------------------------------------------------

Data.Listen("entry", function(createdNew, wasPending)
    if not tab then return end
    LoadEntry()
    if Data.HasEntry() then
        -- Blizzard's own frame plays the sound for a new listing; an edit the
        -- player made from this window is silent there
        if wasPending and not createdNew then PlaySound(SOUNDKIT.PVP_ENTER_QUEUE) end
        if (createdNew or wasPending) and UI.tabs[2] then UI:SelectTab(2) end
    else
        if wasPending then PlaySound(SOUNDKIT.LFG_DENIED) end
        SetDirty(IsAnySelected())
    end
    UpdateButtonText()
    UpdateView()
end)

Data.Listen("availability", function()
    if not tab then return end
    ClearCategory()
    LoadEntry()
end)

Data.Listen("roles", LoadSoloRoles)

Data.Listen("group", function()
    if not tab then return end
    UpdateButtonText()
    UpdateView()
    UpdateGroupRole()
end)

-- A group left with no listing up: what the form held came from the group
Data.Listen("groupLeft", function(home)
    if tab and home and not Data.HasEntry() then ClearCategory() end
end)

Data.Listen("groupRoles", UpdateGroupRole)

Data.Listen("locks", function()
    if tab and form.view == VIEW_ACTIVITIES and P.activityView:IsVisible() then RefreshTree() end
end)

Data.Listen("filter", function()
    if not tab then return end
    UpdateActivities()
    if form.view == VIEW_CATEGORIES then
        RefreshCategories()
    elseif form.view == VIEW_ACTIVITIES and P.activityView:IsVisible() then
        RefreshTree()
    end
    UpdatePostButton()
end)

--------------------------------------------------------------------------------
-- Debug and registration
--------------------------------------------------------------------------------

function Listing.Dump(push)
    push("form: category %s, view %d, dirty %s, playstyle %s, voice mode %s, comment required %s, selected %d",
        tostring(form.category), form.view, tostring(form.dirty), tostring(form.playstyle),
        tostring(form.voiceMode), tostring(form.commentRequired), CountSelected())
    if P.post then
        push("  Post enabled: %s, reason: %s; tree view built: %s", tostring(P.post:IsEnabled()),
            tostring(P.post.errorText), tostring(treeView ~= nil))
    end
end

UI.RegisterTab(1, {
    build = Listing.Build,
    icon = "Interface\\ICONS\\INV_SideTab_GroupFinder_c60",
    tooltip = LFG_LIST_TAB_1,
})
