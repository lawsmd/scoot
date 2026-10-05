-- viewer.lua - Your listing: its name, activity, details and requirement
-- with the party's own grid, the applicants in bands under their column
-- names, and Delist, Edit and Browse Groups under them.
--
-- Blizzard's hidden viewer stays its active panel and keeps acting on its
-- own: it refreshes the applicants on its show and drops a stale one for a
-- member who may not act, so this panel only reads. Every applicant event
-- re-reads the client's list into the component's copy, sorted as Blizzard
-- sorts, and a band per applicant draws a line per member, with the status
-- word, Invite and Decline on its right, each one call from its click. Edit
-- opens the listing form's own edit view (create.lua); auto-accept is
-- written with the listing's own fields, since Blizzard's helper reads a
-- field the listing does not carry.
local addonName, addon = ...

local GF = addon.GroupFinder
local UI = GF.UI
local LAYOUT = UI.LAYOUT
local Str = GF.Str

local function Controls()
    return addon.UI.Controls
end

local function Theme()
    return addon.UI.Theme
end

local function M()
    return addon.UI.Controls.Metrics()
end

local function Viewer()
    return LFGListFrame and LFGListFrame.ApplicationViewer
end

local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }

-- The statuses a member draws grayed, as Blizzard's row grays them
local GRAYED = {
    failed = true, cancelled = true, declined = true, declined_full = true, declined_delisted = true,
    invitedeclined = true, timedout = true, inviteaccepted = true,
}

-- The party's units, the player first
local UNITS = { "player", "party1", "party2", "party3", "party4" }

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

-- The word a status draws, and whether it is lit, as Blizzard's row
-- decides them; none for an application still open
local function StatusWord(status)
    if status == "invited" then return Str("LFG_LIST_APP_INVITED", "Invited"), true end
    if status == "failed" or status == "cancelled" then return Str("LFG_LIST_APP_CANCELLED", "Cancelled"), false end
    if GF.IsDeclined(status) then return Str("LFG_LIST_APP_DECLINED", "Declined"), false end
    if status == "timedout" then return Str("LFG_LIST_APP_TIMED_OUT", "Timed out"), false end
    if status == "inviteaccepted" then return Str("LFG_LIST_APP_INVITE_ACCEPTED", "Accepted"), true end
    if status == "invitedeclined" then return Str("LFG_LIST_APP_INVITE_DECLINED", "Invite declined"), false end
    return nil, false
end

--------------------------------------------------------------------------------
-- The rows
--------------------------------------------------------------------------------

local function Build(parent)
    local panel = UI.MakePanel(parent)
    local C = Controls()
    local V = LAYOUT.viewer
    local R = LAYOUT.search.roster
    local Cn = LAYOUT.search.counts
    local boxX = LAYOUT.panel.boxX
    local pad = (M().collapsible or {}).contentPadding or 12
    local padX = (M().listRow or {}).padX or 8

    -- The heading is the listing's name; the tags stand at its right, off
    -- the panel's corner, and the heading ends at the leftmost shown one
    panel._heading = UI.MakeHeading(panel, "")
    panel._heading:SetWordWrap(false)
    panel._private = C.CreateTag(panel, { text = "PRIVATE", tone = "dim" })
    panel._private:Hide()
    panel._voice = C.CreateTag(panel, { text = "VOICE", tone = "dim" })
    panel._voice:Hide()

    -- The shown tags from the corner leftward, then the heading's right
    -- edge; the heading depends on the tags and never the other way
    function panel:PlaceTags()
        local last
        for _, tag in ipairs({ self._private, self._voice }) do
            if tag:IsShown() then
                tag:ClearAllPoints()
                if last then
                    tag:SetPoint("RIGHT", last, "LEFT", -V.tagGap, 0)
                else
                    tag:SetPoint("TOPRIGHT", self, "TOPRIGHT", -boxX, -(LAYOUT.panel.headingY + V.tagTop))
                end
                last = tag
            end
        end
        self._heading:ClearAllPoints()
        self._heading:SetPoint("TOPLEFT", self, "TOPLEFT", LAYOUT.panel.headingX, -LAYOUT.panel.headingY)
        if last then
            self._heading:SetPoint("RIGHT", last, "LEFT", -V.tagGap, 0)
        else
            self._heading:SetPoint("RIGHT", self, "RIGHT", -boxX, 0)
        end
    end
    panel:PlaceTags()

    local box = UI.MakeBox(panel)
    panel._box = box

    -- The info block: the activity, the details and the requirement at the
    -- left, the party's grid at the right, auto-accept at the bottom
    local info = CreateFrame("Frame", nil, box)
    info:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -pad)
    info:SetPoint("TOPRIGHT", box, "TOPRIGHT", -pad, -pad)
    info:SetHeight(V.infoHeight)
    panel._info = info

    panel._roster = C.CreateRoster(info, {
        lines = R.lines, lineHeight = R.lineHeight, width = LAYOUT.search.rightColumn, fontSize = R.fontSize,
        glyphWidth = R.glyphWidth, gap = R.gap, markWidth = R.markWidth, markHeight = R.markHeight,
        markY = R.markY, iconSize = R.iconSize, icons = UI.RoleIcons(), leaderMark = UI.LEADER_MARK,
    })
    panel._roster:SetPoint("TOPRIGHT", info, "TOPRIGHT", 0, 0)
    panel._counts = C.CreateRoster(info, {
        lines = Cn.lines, lineHeight = Cn.lineHeight, width = Cn.width, fontSize = Cn.fontSize,
        glyphWidth = Cn.glyphWidth, gap = Cn.gap, iconSize = Cn.iconSize, icons = UI.RoleIcons(),
    })
    panel._counts:SetPoint("TOPRIGHT", info, "TOPRIGHT", 0, 0)

    panel._activity = UI.DimText(info, "desc", V.subSize)
    panel._activity:SetPoint("TOPLEFT", info, "TOPLEFT", 0, 0)
    panel._activity:SetPoint("RIGHT", panel._roster, "LEFT", -LAYOUT.search.columnGap, 0)
    panel._activity:SetWordWrap(false)
    panel._comment = UI.DimText(info, "desc", V.subSize)
    panel._comment:SetPoint("TOPLEFT", panel._activity, "BOTTOMLEFT", 0, -V.lineGap)
    panel._comment:SetPoint("RIGHT", panel._activity, "RIGHT", 0, 0)
    panel._comment:SetWordWrap(false)
    local lr, lg, lb = Theme():GetDimTextLightColor()
    panel._comment:SetTextColor(lr, lg, lb, 1)
    panel._ilvl = UI.DimText(info, "desc", V.subSize)
    panel._ilvl:SetPoint("TOPLEFT", panel._comment, "BOTTOMLEFT", 0, -V.lineGap)
    panel._ilvl:SetPoint("RIGHT", panel._activity, "RIGHT", 0, 0)
    panel._ilvl:SetWordWrap(false)

    panel._auto = C.CreateCheckBox(info, { clickable = true, onClick = function() panel:ToggleAutoAccept() end })
    panel._auto:SetPoint("BOTTOMLEFT", info, "BOTTOMLEFT", 0, 0)
    panel._autoLabel = UI.PrimaryText(info, "desc")
    panel._autoLabel:SetPoint("LEFT", panel._auto, "RIGHT", LAYOUT.create.checkGap, 0)
    panel._autoLabel:SetText(Str("LFG_LIST_AUTO_ACCEPT", "Auto accept"))
    panel._autoLabel:SetWordWrap(false)

    -- The column strip, with the refresh arrow over the actions column
    panel._header = C.CreateColumnHeader({
        parent = box,
        columns = {
            { key = "name", label = Str("NAME", "Name") },
            { key = "role", label = Str("ROLE", "Role"), width = V.columns.role },
            { key = "ilvl", label = Str("ITEM_LEVEL_ABBR", "iLvl"), width = V.columns.ilvl, justify = "CENTER" },
            { key = "rating", label = Str("RATING", "Rating"), width = V.columns.rating, justify = "CENTER" },
            { key = "actions", label = "", width = V.columns.actions },
        },
    })
    panel._header:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -pad)
    panel._header:SetPoint("TOPRIGHT", info, "BOTTOMRIGHT", 0, -pad)
    panel._refresh = UI.MakeButton(box, "\226\158\156", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if C_LFGList.RefreshApplicants then C_LFGList.RefreshApplicants() end
    end, V.buttonHeight, Str("LFG_LIST_REFRESH", "Refresh"))
    panel._refresh:SetHeight(V.buttonHeight)
    panel._refresh:SetPoint("RIGHT", panel._header, "RIGHT", -padX, 0)

    -- A line per member on an applicant's band, built as the band needs it
    local function MemberLine(row, i)
        local line = row._members[i]
        if line then return line end
        line = CreateFrame("Frame", nil, row)
        line:SetHeight(V.memberLine)
        local y = -(V.rowPad / 2 + (i - 1) * V.memberLine)
        line:SetPoint("TOPLEFT", row, "TOPLEFT", padX, y)
        line:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(padX + V.columns.actions), y)

        -- The cells from the right: rating, item level, roles; the name
        -- and its tags take the rest
        line._rating = UI.PrimaryText(line, "desc", V.subSize)
        line._rating:SetJustifyH("CENTER")
        line._rating:SetPoint("RIGHT", line, "RIGHT", 0, 0)
        line._rating:SetWidth(V.columns.rating)
        line._ilvl = UI.PrimaryText(line, "desc", V.subSize)
        line._ilvl:SetJustifyH("CENTER")
        line._ilvl:SetPoint("RIGHT", line._rating, "LEFT", 0, 0)
        line._ilvl:SetWidth(V.columns.ilvl)
        local roles = CreateFrame("Frame", nil, line)
        roles:SetSize(V.columns.role, V.memberLine)
        roles:SetPoint("RIGHT", line._ilvl, "LEFT", 0, 0)
        line._roles = roles
        line._roleButtons = {}
        local icons = UI.RoleIcons()
        for n, role in ipairs(ROLE_ORDER) do
            local button = CreateFrame("Button", nil, roles)
            button:SetSize(V.roleIcon, V.roleIcon)
            button:SetPoint("LEFT", roles, "LEFT", (n - 1) * (V.roleIcon + V.roleGap), 0)
            button:RegisterForClicks("LeftButtonUp")
            local tex = button:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints(button)
            if icons and icons[role] then
                tex:SetAtlas(icons[role])
                tex:SetDesaturated(true)
            end
            button._tex = tex
            button._role = role
            button:SetScript("OnClick", function() panel:AssignRole(row, i, role) end)
            button:Hide()
            line._roleButtons[n] = button
        end

        line._leaver = C.CreateTag(line, { text = "LEAVER", tone = "dim" })
        line._leaver:SetPoint("RIGHT", roles, "LEFT", -V.tagGap, 0)
        line._leaver:Hide()
        line._friend = C.CreateTag(line, { text = "FRIEND", tone = "dim" })
        line._friend:SetPoint("RIGHT", roles, "LEFT", -V.tagGap, 0)
        line._friend:Hide()
        line._name = UI.PrimaryText(line, "label", V.nameSize)
        line._name:SetPoint("LEFT", line, "LEFT", 0, 0)
        line._name:SetPoint("RIGHT", roles, "LEFT", -V.tagGap, 0)
        line._name:SetWordWrap(false)
        row._members[i] = line
        return line
    end

    local function CreateRow(row)
        row._members = {}
        row._status = C.CreateTag(row, { text = "", tone = "dim" })
        row._status:Hide()
        row._invite = UI.MakeButton(row, Str("INVITE", "Invite"), function() panel:Invite(row) end,
            V.inviteWidth, function() return row._inviteReason end)
        row._invite:SetHeight(V.buttonHeight)
        row._invite:Hide()
        row._decline = UI.MakeButton(row, "x", function() panel:Decline(row) end, V.declineWidth)
        row._decline:SetHeight(V.buttonHeight)
        row._decline:Hide()
    end

    -- The name in the class color, the tags, the roles offered with the
    -- assigned one lit, the item level and the rating; a grayed member
    -- keeps the name alone
    local function RenderMember(line, m, grayed, noTouch, kind, id, i)
        local theme = Theme()
        theme:ApplyFont(line._name, "label", V.nameSize)
        theme:ApplyFont(line._ilvl, "desc", V.subSize)
        theme:ApplyFont(line._rating, "desc", V.subSize)
        local text = ""
        if m and type(m.rawName) == "string" then text = Ambiguate(m.rawName, "short") end
        line._name:SetText(text)
        local r, g, b
        if grayed or not m then
            r, g, b = theme:GetDimTextColor()
        elseif m.class then
            r, g, b = addon.GetClassColorRGB(m.class)
        end
        if not r then r, g, b = theme:GetPrimaryTextColor() end
        line._name:SetTextColor(r, g, b, 1)

        local leaver = m ~= nil and m.leaver and not grayed
        local friend = m ~= nil and m.relationship ~= nil and not grayed
        line._leaver:SetShown(leaver)
        line._friend:SetShown(friend)
        if friend then
            line._friend:SetText(m.relationship == "guild" and "GUILD" or "FRIEND")
            line._friend:ClearAllPoints()
            line._friend:SetPoint("RIGHT", line._roles, "LEFT", -V.tagGap, 0)
            if leaver then
                line._leaver:ClearAllPoints()
                line._leaver:SetPoint("RIGHT", line._friend, "LEFT", -V.tagGap, 0)
            end
        elseif leaver then
            line._leaver:ClearAllPoints()
            line._leaver:SetPoint("RIGHT", line._roles, "LEFT", -V.tagGap, 0)
        end
        local after = (leaver and line._leaver) or (friend and line._friend) or line._roles
        line._name:SetPoint("RIGHT", after, "LEFT", -V.tagGap, 0)

        -- The roles the member offers, in role order, the assigned one in
        -- the accent and the rest dim; a click assigns, unless invited
        local ar, ag, ab = theme:GetAccentColor()
        local dr, dg, db = theme:GetDimTextColor()
        local offered = m and { TANK = m.tank, HEALER = m.healer, DAMAGER = m.damage } or {}
        local slot = 0
        for _, button in ipairs(line._roleButtons) do
            local role = button._role
            local show = not grayed and offered[role] == true
            button:SetShown(show)
            if show then
                button:ClearAllPoints()
                button:SetPoint("LEFT", line._roles, "LEFT", slot * (V.roleIcon + V.roleGap), 0)
                slot = slot + 1
                local assigned = m.assignedRole == role
                if assigned then
                    button._tex:SetVertexColor(ar, ag, ab, 1)
                else
                    button._tex:SetVertexColor(dr, dg, db, 0.6)
                end
                button:SetEnabled(not noTouch and not assigned)
            end
        end

        if grayed or not m then
            line._ilvl:SetText("")
            line._rating:SetText("")
            return
        end
        local ilvl = kind.pvp and m.pvpItemLevel or m.itemLevel
        line._ilvl:SetText(ilvl and tostring(math.floor(ilvl)) or "")
        local pr, pg, pb = theme:GetPrimaryTextColor()
        line._ilvl:SetTextColor(pr, pg, pb, 1)
        line._rating:SetText("")
        if panel._showRating then
            if kind.rated and C_LFGList.GetApplicantPvpRatingInfoForListing and panel._activityID then
                local ok, pvp = pcall(C_LFGList.GetApplicantPvpRatingInfoForListing, id, i, panel._activityID)
                local rating = ok and type(pvp) == "table" and GF.plainNumber(pvp.rating)
                if rating then
                    line._rating:SetText(tostring(rating))
                    line._rating:SetTextColor(pr, pg, pb, 1)
                end
            elseif m.dungeonScore then
                line._rating:SetText(tostring(m.dungeonScore))
                local color = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
                    and C_ChallengeMode.GetDungeonScoreRarityColor(m.dungeonScore)
                if color and color.GetRGB then
                    line._rating:SetTextColor(color:GetRGB())
                else
                    line._rating:SetTextColor(pr, pg, pb, 1)
                end
            end
        end
    end

    -- The band: a line per member, then the status word, Invite and
    -- Decline from the right as Blizzard's row shows them for the status
    local function RenderRow(row, item)
        local id = item.id
        row._id = id
        local n = math.max(1, item.numMembers or 1)
        row._numMembers = n
        local applicant = GF.ApplicantInfo(id)
        local status = applicant and GF.plain(applicant.applicationStatus) or "applied"
        local pending = applicant and GF.plain(applicant.pendingApplicationStatus)
        local grayed = pending == nil and GRAYED[status] == true
        local noTouch = status == "invited"
        local kind = panel._kind or {}
        for i = 1, n do
            local line = MemberLine(row, i)
            RenderMember(line, GF.ApplicantMember(id, i), grayed, noTouch, kind, id, i)
            line:Show()
        end
        for i = n + 1, #row._members do
            row._members[i]:Hide()
        end

        local canAct = GF.CanManageEntry()
        local showInvite = status == "applied" and canAct
        local showDecline = status ~= "invited" and canAct
        row._isAck = status ~= "applied" and status ~= "invited"
        local right = -padX
        row._decline:SetShown(showDecline)
        if showDecline then
            row._decline:ClearAllPoints()
            row._decline:SetPoint("RIGHT", row, "RIGHT", right, 0)
            right = right - V.declineWidth - V.actionGap
        end
        row._invite:SetShown(showInvite)
        if showInvite then
            row._invite:ClearAllPoints()
            row._invite:SetPoint("RIGHT", row, "RIGHT", right, 0)
            right = right - V.inviteWidth - V.actionGap
            local reason = panel:InviteBlock(n)
            row._inviteReason = reason
            row._invite:SetEnabled(reason == nil)
        end
        local word, lit = StatusWord(status)
        if word then
            row._status:SetTone(lit and "accent" or "dim")
            row._status:SetText(word)
            row._status:ClearAllPoints()
            row._status:SetPoint("RIGHT", row, "RIGHT", right, 0)
            row._status:Show()
        else
            row._status:Hide()
        end
        row._backdrop:SetStatus(nil)
    end

    local list = C.CreateScrollList({
        parent = box,
        rowHeight = function(item) return V.memberLine * math.max(1, item.numMembers or 1) + V.rowPad end,
        wheelStep = V.memberLine + V.rowPad,
        createRow = CreateRow,
        render = RenderRow,
        onRightClick = function(item) panel:OpenRowMenu(item.id) end,
        onEnter = function(item, _, row) panel:ShowTooltip(row, item.id) end,
        onLeave = function() GameTooltip:Hide() end,
    })
    list.frame:SetPoint("TOPLEFT", panel._header, "BOTTOMLEFT", 0, 0)
    list.frame:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -pad, pad)
    panel._list = list

    panel._empty = C.CreateEmptyState({ parent = box, text = Str("LFG_LIST_NO_APPLICANTS", "No applicants") })
    panel._empty:SetAllPoints(list.frame)
    panel._empty:Hide()

    -- The cover for a member who may not act on the listing
    local cover = CreateFrame("Frame", nil, box)
    cover:SetAllPoints(list.frame)
    cover:SetFrameLevel(list.frame:GetFrameLevel() + 20)
    cover:EnableMouse(true)
    C.AddBackground(cover, { color = "collapsible" })
    cover:SetAlpha(LAYOUT.create.coverAlpha)
    cover._empty = C.CreateEmptyState({ parent = cover, text = "" })
    cover._empty:SetAllPoints(cover)
    cover:Hide()
    panel._cover = cover

    -- The bottom edge
    panel._delist = UI.MakeButton(panel, Str("GROUP_FINDER_DELIST", "Delist"), function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        C_LFGList.RemoveListing()
    end, LAYOUT.buttonWidth)
    panel._delist:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LAYOUT.panel.buttonX, LAYOUT.panel.buttonY)
    panel._edit = UI.MakeButton(panel, Str("EDIT", "Edit"), function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if UI.Create then UI.Create:Edit() end
    end, nil, function() return panel._editReason end)
    panel._edit:SetPoint("RIGHT", panel._delist, "LEFT", -V.actionGap, 0)
    panel._browse = UI.MakeButton(panel, Str("GROUP_FINDER_BROWSE", "Browse Groups"), function()
        panel:Browse()
    end, nil, function()
        if not GF.SearchAllowed() then
            return string.format("Searching again in %d s", math.ceil(GF.SearchCooldownLeft()))
        end
        return nil
    end)
    panel._browse:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LAYOUT.panel.buttonX, LAYOUT.panel.buttonY)

    -- The row menu
    panel._menu = C.CreatePopupList({
        width = 200,
        getKeys = function() return { "whisper", "report", "ignore" } end,
        getValues = function()
            return {
                whisper = Str("WHISPER", "Whisper"),
                report = Str("LFG_LIST_REPORT_PLAYER", "Report player"),
                ignore = Str("IGNORE_PLAYER", "Ignore"),
            }
        end,
        getSelectedKey = function() return nil end,
        isInert = function(key) return key ~= "report" and not panel._menuName end,
        onSelect = function(key) panel:MenuAction(key) end,
    })

    ----------------------------------------------------------------------------
    -- The actions
    ----------------------------------------------------------------------------

    -- Why Invite is off: the group is full, or the invites out already
    -- fill it, as Blizzard's viewer tests
    function panel:InviteBlock(numMembers)
        local activity = GF.ActivityInfo(self._activityID)
        local allowed = activity and GF.plainNumber(activity.maxNumPlayers) or 0
        if allowed == 0 then allowed = MAX_RAID_MEMBERS or 40 end
        local members = GetNumGroupMembers(LE_PARTY_CATEGORY_HOME)
        local invited = C_LFGList.GetNumInvitedApplicantMembers and C_LFGList.GetNumInvitedApplicantMembers() or 0
        if numMembers + members > allowed then
            return Str("LFG_LIST_GROUP_TOO_FULL", "The group is full")
        end
        if numMembers + members + (GF.plainNumber(invited) or 0) > allowed then
            return Str("LFG_LIST_INVITED_APP_FILLS_GROUP", "The invites out fill the group")
        end
        return nil
    end

    -- Past a party's size the client asks about a raid first, through
    -- Blizzard's own popup, whose accept invites
    function panel:Invite(row)
        local id = row._id
        if not id then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        local home = LE_PARTY_CATEGORY_HOME
        local invited = C_LFGList.GetNumInvitedApplicantMembers and C_LFGList.GetNumInvitedApplicantMembers() or 0
        local partyMax = (MAX_PARTY_MEMBERS or 4) + 1
        if not IsInRaid(home) and GetNumGroupMembers(home) + (row._numMembers or 1) + (GF.plainNumber(invited) or 0) > partyMax then
            if StaticPopup_Show then StaticPopup_Show("LFG_LIST_INVITING_CONVERT_TO_RAID", nil, nil, id) end
        else
            C_LFGList.InviteApplicant(id)
        end
    end

    -- Decline an open application; clear a finished one away
    function panel:Decline(row)
        local id = row._id
        if not id then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if row._isAck then
            C_LFGList.RemoveApplicant(id)
        else
            C_LFGList.DeclineApplicant(id)
        end
    end

    function panel:AssignRole(row, memberIndex, role)
        local id = row._id
        if not (id and C_LFGList.SetApplicantMemberRole) then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        C_LFGList.SetApplicantMemberRole(id, memberIndex, role)
    end

    -- Auto-accept written with the listing's own fields after the client
    -- copies its text back into the creation boxes, as Blizzard's helper
    -- does, with the cross-faction flag the listing carries
    function panel:ToggleAutoAccept()
        if self._autoInert then return end
        local entry = GF.ActiveEntry()
        if not entry then return end
        local on = not self._auto:IsChecked()
        self._auto:SetChecked(on)
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if C_LFGList.CopyActiveEntryInfoToCreationFields then C_LFGList.CopyActiveEntryInfoToCreationFields() end
        local ids = GF.plain(entry.activityIDs)
        C_LFGList.UpdateListing({
            activityIDs = type(ids) == "table" and { GF.plainNumber(ids[1]) } or { self._activityID },
            questID = GF.plainNumber(entry.questID),
            isAutoAccept = on,
            isCrossFactionListing = GF.plainBool(entry.isCrossFactionListing) == true,
            isPrivateGroup = GF.plainBool(entry.privateGroup) == true,
            playstyle = GF.plainNumber(entry.playstyle) or 0,
            generalPlaystyle = GF.plainNumber(entry.generalPlaystyle) or 0,
            requiredDungeonScore = GF.plainNumber(entry.requiredDungeonScore) or 0,
            requiredItemLevel = GF.plainNumber(entry.requiredItemLevel) or 0,
            requiredPvpRating = GF.plainNumber(entry.requiredPvpRating) or 0,
        })
    end

    -- Browse Groups runs Blizzard's own handler with its button, which
    -- searches the listing's category; the host's hook notes the search
    function panel:Browse()
        local viewer = Viewer()
        local mixin = LFGApplicationBrowseGroupsButtonMixin
        if not (viewer and viewer.BrowseGroupsButton and mixin and mixin.OnClick) then return end
        if not GF.SearchAllowed() then
            self:RefreshButtons()
            return
        end
        mixin.OnClick(viewer.BrowseGroupsButton)
    end

    ----------------------------------------------------------------------------
    -- The row's tooltip and menu
    ----------------------------------------------------------------------------

    function panel:ShowTooltip(row, id)
        local n = row._numMembers or 1
        local kind = self._kind or {}
        local theme = Theme()
        local dr, dg, db = theme:GetDimTextColor()
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT", 25, 0)
        GameTooltip:ClearLines()
        pcall(function()
            for i = 1, n do
                local m = GF.ApplicantMember(id, i)
                if m then
                    local r, g, b = 1, 1, 1
                    if m.class then r, g, b = addon.GetClassColorRGB(m.class) end
                    if type(m.rawName) == "string" then
                        GameTooltip:AddLine(Ambiguate(m.rawName, "short"), r or 1, g or 1, b or 1)
                    end
                    local spec = m.specID and PlayerUtil and PlayerUtil.GetSpecNameBySpecID
                        and PlayerUtil.GetSpecNameBySpecID(m.specID)
                    local who = m.className
                    if type(spec) == "string" and who then who = spec .. " " .. who end
                    if m.level and who then
                        GameTooltip:AddLine(string.format(Str("UNIT_TYPE_LEVEL_TEMPLATE", "Level %d %s"), m.level, who), dr, dg, db)
                    end
                    local ilvl = kind.pvp and m.pvpItemLevel or m.itemLevel
                    if ilvl then
                        local key = kind.pvp and "LFG_LIST_ITEM_LEVEL_CURRENT_PVP" or "LFG_LIST_ITEM_LEVEL_CURRENT"
                        GameTooltip:AddLine(string.format(Str(key, "Item level %d"), math.floor(ilvl)), dr, dg, db)
                    end
                    if m.leaver then
                        GameTooltip:AddLine(Str("MYTHIC_PLUS_DESERTER", "Leaver"), 1, 0.3, 0.3)
                    end
                    if m.relationship then
                        local key = m.relationship == "guild" and "LFG_LIST_GUILD_MEMBER" or "FRIEND"
                        GameTooltip:AddLine(Str(key, "Friend"), theme:GetAccentColor())
                    end
                    if self._showRating and m.dungeonScore and not kind.rated then
                        GameTooltip:AddLine(string.format(Str("DUNGEON_SCORE", "Rating: %d"), m.dungeonScore), dr, dg, db)
                        if C_LFGList.GetApplicantDungeonScoreForListing and self._activityID then
                            local ok, best = pcall(C_LFGList.GetApplicantDungeonScoreForListing, id, i, self._activityID)
                            local level = ok and type(best) == "table" and GF.plainNumber(best.bestRunLevel)
                            local map = ok and type(best) == "table" and GF.plain(best.mapName)
                            if level and level > 0 and type(map) == "string" then
                                GameTooltip:AddLine(string.format("%s +%d", map, level), dr, dg, db)
                            end
                        end
                    end
                end
            end
            local applicant = GF.ApplicantInfo(id)
            if applicant and NonEmpty(applicant.comment) then
                GameTooltip:AddLine(string.format(Str("LFG_LIST_COMMENT_FORMAT", "\"%s\""), applicant.comment), 1, 1, 1, true)
            end
        end)
        GameTooltip:Show()
    end

    -- The menu for the applicant's first member, as Blizzard's is per member
    function panel:OpenRowMenu(id)
        local m = GF.ApplicantMember(id, 1)
        self._menuID = id
        self._menuName = m and m.name or nil
        self._menu:OpenAtCursor()
    end

    function panel:MenuAction(key)
        local id = self._menuID
        if not id then return end
        if key == "whisper" then
            if self._menuName and ChatFrameUtil and ChatFrameUtil.SendTell then ChatFrameUtil.SendTell(self._menuName) end
        elseif key == "report" then
            if LFGList_ReportApplicant then LFGList_ReportApplicant(id, self._menuName or "") end
        elseif key == "ignore" then
            if self._menuName and C_FriendList and C_FriendList.AddIgnore then
                C_FriendList.AddIgnore(self._menuName)
                C_LFGList.DeclineApplicant(id)
            end
        end
    end

    ----------------------------------------------------------------------------
    -- Refresh
    ----------------------------------------------------------------------------

    -- The party's own grid: a line per member from the client's unit reads
    -- for an activity the grid holds, the class name as the text and the
    -- player's own spec; the counts grid past it
    function panel:RenderParty(activity)
        local max = activity and GF.plainNumber(activity.maxNumPlayers) or 0
        if max > 0 and max <= R.lines then
            local byRole = { TANK = {}, HEALER = {}, DAMAGER = {} }
            for _, unit in ipairs(UNITS) do
                if UnitExists(unit) then
                    local role = UnitGroupRolesAssigned(unit)
                    if not byRole[role] then role = "DAMAGER" end
                    local className, class = UnitClass(unit)
                    local text = className
                    if unit == "player" and GetSpecialization and GetSpecializationInfo then
                        local _, spec = GetSpecializationInfo(GetSpecialization() or 0)
                        if type(spec) == "string" and spec ~= "" then text = spec end
                    end
                    local cr, cg, cb
                    if class then cr, cg, cb = addon.GetClassColorRGB(class) end
                    local leader = UnitIsGroupLeader(unit, LE_PARTY_CATEGORY_HOME)
                        or (unit == "player" and not IsInGroup(LE_PARTY_CATEGORY_HOME))
                    local entry = {
                        role = role, filled = true, color = cr and { cr, cg, cb } or nil,
                        text = type(text) == "string" and text or nil, leader = leader and true or false,
                    }
                    if leader then
                        table.insert(byRole[role], 1, entry)
                    else
                        byRole[role][#byRole[role] + 1] = entry
                    end
                end
            end
            local entries = {}
            for _, role in ipairs(ROLE_ORDER) do
                for _, entry in ipairs(byRole[role]) do entries[#entries + 1] = entry end
            end
            while #entries > max do table.remove(entries) end
            self._counts:SetLines({})
            self._roster:SetLines(entries)
            self._roster:Show()
            self._counts:Hide()
            return
        end
        local counts = GetGroupMemberCountsForDisplay and GetGroupMemberCountsForDisplay() or {}
        local lr2, lg2, lb2 = Theme():GetDimTextLightColor()
        local light = { lr2, lg2, lb2 }
        local entries = {}
        for _, role in ipairs(ROLE_ORDER) do
            entries[#entries + 1] = {
                role = role, filled = true, color = light,
                text = tostring(GF.plainNumber(counts[role]) or 0),
            }
        end
        self._roster:SetLines({})
        self._counts:SetLines(entries)
        self._roster:Hide()
        self._counts:Show()
    end

    function panel:RefreshInfo()
        local entry = GF.ActiveEntry()
        local theme = Theme()
        theme:ApplyFont(self._activity, "desc", V.subSize)
        theme:ApplyFont(self._comment, "desc", V.subSize)
        theme:ApplyFont(self._ilvl, "desc", V.subSize)
        if not entry then
            self._heading:SetText("")
            self._activity:SetText("")
            self._comment:SetText("")
            self._ilvl:SetText("")
            self._private:Hide()
            self._voice:Hide()
            self:PlaceTags()
            self._roster:SetLines({})
            self._counts:SetLines({})
            self._auto:Hide()
            self._autoLabel:Hide()
            return
        end
        local ids = GF.plain(entry.activityIDs)
        self._activityID = type(ids) == "table" and GF.plainNumber(ids[1]) or nil
        local activity = GF.ActivityInfo(self._activityID)
        local pvp = activity ~= nil and GF.plainBool(activity.isPvpActivity) == true
        local mplus = activity ~= nil and GF.plainBool(activity.isMythicPlusActivity) == true
        local rated = activity ~= nil and GF.plainBool(activity.isRatedPvpActivity) == true
        self._kind = { pvp = pvp, mplus = mplus, rated = rated }
        self._showRating = mplus or rated

        SetTextSafe(self._heading, entry.name)
        self._private:SetShown(GF.plainBool(entry.privateGroup) == true)
        self._voice:SetShown(NonEmpty(entry.voiceChat))
        self:PlaceTags()
        SetTextSafe(self._activity, GF.ActivityName(entry))
        local questID = GF.plainNumber(entry.questID)
        if NonEmpty(entry.comment) then
            self._comment:SetText(entry.comment)
        elseif questID and LFGListUtil_GetQuestDescription then
            SetTextSafe(self._comment, LFGListUtil_GetQuestDescription(questID))
        else
            self._comment:SetText("")
        end
        local ilvl = GF.plainNumber(entry.requiredItemLevel) or 0
        if ilvl > 0 then
            local key = pvp and "LFG_LIST_ITEM_LEVEL_CURRENT_PVP" or "LFG_LIST_ITEM_LEVEL_CURRENT"
            self._ilvl:SetText(string.format(Str(key, "Item level %d"), ilvl))
        else
            self._ilvl:SetText("")
        end
        self:RenderParty(activity)

        -- Auto-accept as Blizzard shows it: the leader may set it, an
        -- assistant sees it, anyone else sees it only while it is on
        local home = LE_PARTY_CATEGORY_HOME
        local usable = C_LFGList.CanActiveEntryUseAutoAccept and C_LFGList.CanActiveEntryUseAutoAccept()
        local on = GF.plainBool(entry.autoAccept) == true
        local show, inert
        if not usable then
            show = false
        elseif UnitIsGroupLeader("player", home) then
            show, inert = true, false
        elseif UnitIsGroupAssistant("player", home) then
            show, inert = true, true
        else
            show, inert = on, true
        end
        self._autoInert = inert and true or false
        self._auto:SetShown(show)
        self._autoLabel:SetShown(show)
        self._auto:SetChecked(on)
        local r, g, b
        if inert then r, g, b = theme:GetDimTextColor() else r, g, b = theme:GetAccentColor() end
        self._auto:SetColor(r, g, b, 1)
        local lr3, lg3, lb3
        if inert then lr3, lg3, lb3 = theme:GetDimTextColor() else lr3, lg3, lb3 = theme:GetPrimaryTextColor() end
        self._autoLabel:SetTextColor(lr3, lg3, lb3, 1)
    end

    -- The rating column comes and goes with the activity
    function panel:RefreshHeader()
        local columns = {
            { key = "name", label = Str("NAME", "Name") },
            { key = "role", label = Str("ROLE", "Role"), width = V.columns.role },
            { key = "ilvl", label = Str("ITEM_LEVEL_ABBR", "iLvl"), width = V.columns.ilvl, justify = "CENTER" },
        }
        if self._showRating then
            columns[#columns + 1] = { key = "rating", label = Str("RATING", "Rating"), width = V.columns.rating, justify = "CENTER" }
        end
        columns[#columns + 1] = { key = "actions", label = "", width = V.columns.actions }
        if self._headerRating ~= self._showRating then
            self._headerRating = self._showRating
            self._header:SetColumns(columns)
        end
    end

    function panel:RefreshList()
        local canAct = GF.CanManageEntry()
        local items = GF.state.applicants
        self._list:SetItems(items)
        self._empty:SetShown(canAct and #items == 0)
        self._cover:SetShown(not canAct)
        self._cover._empty:SetBusy(not canAct, Str("LFG_LIST_GROUP_FORMING", "Waiting for the leader"))
    end

    function panel:RefreshRow(id)
        for i, item in ipairs(self._list._items) do
            if item.id == id then
                local row = self._list:GetRow(i)
                if row and row:IsShown() then RenderRow(row, item) end
                return
            end
        end
    end

    -- Delist and Edit for the leader, Edit off on a restricted account;
    -- Browse Groups for the leader
    function panel:RefreshButtons()
        local leader = UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME)
        self._delist:SetShown(leader)
        self._edit:SetShown(leader)
        self._browse:SetShown(leader)
        local restricted = IsRestrictedAccount and IsRestrictedAccount()
        self._editReason = restricted and Str("ERR_RESTRICTED_ACCOUNT_LFG_LIST_TRIAL", "Not on this account") or nil
        self._edit:SetEnabled(not restricted)
        local allowed = GF.SearchAllowed()
        self._browse:SetEnabled(allowed)
        if not allowed then
            C_Timer.After(GF.SearchCooldownLeft() + 0.05, function()
                if self:IsShown() then self:RefreshButtons() end
            end)
        end
    end

    function panel:Refresh()
        GF.RebuildApplicants()
        self:RefreshInfo()
        self:RefreshHeader()
        self:RefreshList()
        self:RefreshButtons()
    end

    function panel:Cleanup()
        self._list:Cleanup()
        self._header:Cleanup()
        self._menu:Destroy()
    end

    panel:HookScript("OnHide", function()
        panel._menu:Close()
    end)

    GF.Listen("applicants", function()
        if panel:IsShown() then
            panel:RefreshList()
            panel:RefreshButtons()
        end
    end)
    GF.Listen("applicant", function(id)
        if panel:IsShown() then panel:RefreshRow(id) end
    end)
    GF.Listen("entry", function()
        if panel:IsShown() then panel:Refresh() end
    end)
    GF.Listen("buttons", function()
        if panel:IsShown() then
            panel:RefreshInfo()
            panel:RefreshList()
            panel:RefreshButtons()
        end
    end)
    GF.Listen("lockdown", function()
        if panel:IsShown() then panel:Refresh() end
    end)

    return panel
end

UI.panelBuilders.viewer = Build
