-- create.lua - the listing panel: the group and the activity, the title and
-- the details, the playstyle, the requirements, the two options, and List
-- Group or Done Editing under them.
--
-- Blizzard's hidden creation panel keeps the choice of activity: a dropdown
-- row runs its Select, which fills that panel's fields, shows or hides its
-- rows and writes a Mythic+ title into the name box, and this panel reads
-- those fields back to draw. The title, the details and the voice chat are
-- Blizzard's own boxes, hosted, since the client reads a listing's text from
-- them alone. The requirements and the options are Scoot's, and List Group
-- assembles the listing from them as Blizzard's button does.
--
-- Start a Group runs the steps of Blizzard's Show with one restricted
-- call: Blizzard's order writes the title twice on Dungeons with a
-- keystone, and a second such call in one click is blocked. Editing
-- is this panel's own view: the client copies the listing's text into the
-- boxes, the hidden panel is shown so they render, and Done Editing updates
-- the listing. Blizzard's edit mode is never entered, since its entry
-- writes the title twice as well.
local addonName, addon = ...

local GF = addon.GroupFinder
local UI = GF.UI
local LAYOUT = UI.LAYOUT
local Host = GF.Host
local Str = GF.Str
local SS = addon.SecretSafe

local Create = {}
UI.Create = Create

local function Controls()
    return addon.UI.Controls
end

local function Theme()
    return addon.UI.Theme
end

local function M()
    return addon.UI.Controls.Metrics()
end

local function EC()
    return LFGListFrame and LFGListFrame.EntryCreation
end

-- The template art of a single-line box, and the lock button every box
-- carries, put at alpha 0 while hosted
local BOX_ART = { "Left", "Middle", "Right" }
local LOCK_FRAMES = { "LockButton" }

-- The dropdown keys: a group, an activity, or the finder
local GROUP_PREFIX, ACTIVITY_PREFIX, MORE = "g:", "a:", "more"

-- Blizzard's own rule for its dropdowns: past this many entries the
-- recommended ones stand in and the rest are behind More
local BLIZZARD = { fewEntries = 5, dropdownCap = 17 }

--------------------------------------------------------------------------------
-- The ways in
--------------------------------------------------------------------------------

-- Blizzard's Show step by step, its one restricted call last. Its edit
-- mode is reset only when still on, from Blizzard's own window, and before
-- the clear, since SetEditMode reads the chosen activity and the clear
-- takes it away; this window never turns the mode on. Clear empties the
-- hidden panel and the text boxes; the one Select then takes the
-- keystone's activity for Dungeons, else the category's best, and writes a
-- Mythic+ title (Blizzard's SetEditMode false would pick the keystone a
-- second time, after Select); the hidden panel is shown so the boxes
-- render, never made Blizzard's active panel, the window's view comes up,
-- and the focus lands in the title. Blizzard's CheckAutoCreate is left
-- out, so a stale quest auto-create never lists a group from the window's
-- own button.
function Create:Open(categoryID, filters, baseFilters)
    local lf, ec = LFGListFrame, EC()
    if not (lf and ec and categoryID) then return end
    if not (LFGListEntryCreation_SetBaseFilters and LFGListEntryCreation_Clear
        and LFGListEntryCreation_SetEditMode and LFGListEntryCreation_Select) then
        return
    end
    self:Close()
    self._fresh = true
    LFGListEntryCreation_SetBaseFilters(ec, baseFilters or GF.plainNumber(lf.baseFilters) or 0)
    if GF.plainBool(ec.editMode) == true then
        LFGListEntryCreation_SetEditMode(ec, false)
    end
    LFGListEntryCreation_Clear(ec)
    local keystone, keystoneGroup
    if categoryID == GF.DUNGEONS_CATEGORY then
        keystone, keystoneGroup = GF.OwnedKeystoneActivity()
    end
    if keystone then
        LFGListEntryCreation_Select(ec, filters or 0, categoryID, keystoneGroup, keystone)
    else
        LFGListEntryCreation_Select(ec, filters or 0, categoryID)
    end
    ec:Show()
    UI:SetView("create")
    if ec.Name and ec.Name.SetFocus then ec.Name:SetFocus() end
end

-- The listing's text copied into the boxes by the client, the hidden panel
-- shown so they render, and this panel up in its edit mode; the viewer
-- stays Blizzard's active panel
function Create:Edit()
    local ec = EC()
    if not (ec and GF.ActiveEntry()) then return end
    if C_LFGList.CopyActiveEntryInfoToCreationFields then
        C_LFGList.CopyActiveEntryInfoToCreationFields()
    end
    ec:Show()
    UI.editing = true
    self._fresh = true
    UI:SetView("create")
end

-- The view ends: the hidden panel goes back out of sight unless Blizzard
-- has it active; the caller syncs the window
function Create:Close()
    UI.editing = false
    local lf, ec = LFGListFrame, EC()
    if ec and lf and SS.plainFrame(lf.activePanel) ~= ec then ec:Hide() end
    if UI.view == "create" then UI.view = nil end
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

local function ParseKey(key)
    if type(key) ~= "string" then return nil end
    local kind, id = string.match(key, "^(%a):(%d+)$")
    return kind, tonumber(id)
end

-- A list from one of the client's activity calls, or an empty one
local function Activities(fn, ...)
    if not fn then return {} end
    local ok, list = pcall(fn, ...)
    return (ok and type(list) == "table") and list or {}
end

-- A group's name and its place in the order
local function GroupInfo(groupID)
    if not groupID or not C_LFGList.GetActivityGroupInfo then return nil end
    local ok, name, orderIndex = pcall(C_LFGList.GetActivityGroupInfo, groupID)
    if not ok then return nil end
    name = GF.plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    return name, GF.plainNumber(orderIndex)
end

-- A box's text when it is plain, else nothing
local function BoxText(box)
    if not box or not box.GetText then return "" end
    local ok, text = pcall(box.GetText, box)
    text = ok and GF.plain(text) or nil
    return type(text) == "string" and text or ""
end

-- A key the options do not list, put first, so the chosen entry reads
-- whatever Blizzard's cap left out
local function EnsureKey(values, order, key, label)
    if key and not values[key] then
        values[key] = label or key
        table.insert(order, 1, key)
    end
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

local function Build(parent)
    local panel = UI.MakePanel(parent)
    local C = Controls()
    local L = LAYOUT.create
    local boxX = LAYOUT.panel.boxX
    local pad = (M().collapsible or {}).contentPadding or 12
    local formWidth = LAYOUT.panelWidth - boxX * 2 - pad * 2
    local half = math.floor((formWidth - L.gap) / 2)
    local rightX = half + L.gap + L.columnPad
    local rightWidth = formWidth - rightX
    local rightRows = 5
    local detailsHeight = rightRows * L.rowHeight + (rightRows - 1) * L.rowGap
        - L.captionHeight - L.captionGap - L.gap - L.rowHeight

    panel._heading = UI.MakeHeading(panel, "")
    panel._heading:SetPoint("RIGHT", panel, "RIGHT", -boxX, 0)
    panel._heading:SetWordWrap(false)
    -- The box without its gray or its border; the fields carry the gray
    local box = UI.MakeBox(panel)
    box._bg:Hide()
    for _, edge in pairs(box._border) do edge:Hide() end
    panel._box = box

    -- The form's rows stack inside the box's padding: the rows across the
    -- width, then the two columns under them; Flow lays the shown ones of
    -- each one under the other
    local form = CreateFrame("Frame", nil, box)
    form:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -pad)
    form:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -pad, pad)
    panel._form = form
    panel._rows, panel._left, panel._right = {}, {}, {}

    local function Row(list, height, gap)
        local row = CreateFrame("Frame", nil, form)
        row:SetHeight(height)
        row._gap = gap or L.gap
        list[#list + 1] = row
        return row
    end

    -- The group and the activity side by side, or the listed activity's
    -- name in their place while editing. A dropdown reads its value as it
    -- is made, before the panel's readers below exist, so each getter
    -- tests for its reader first.
    local pick = Row(panel._rows, L.rowHeight)
    panel._pick = pick
    pick._group = C:CreateDropdown({
        parent = pick, width = half, height = L.rowHeight, values = {}, order = {}, placeholder = "",
        get = function() return panel.GroupKey and panel:GroupKey() or nil end,
        set = function(key) panel:PickGroup(key) end,
    })
    pick._group:SetPoint("TOPLEFT", pick, "TOPLEFT", 0, 0)
    pick._activity = C:CreateDropdown({
        parent = pick, width = half, height = L.rowHeight, values = {}, order = {}, placeholder = "",
        get = function() return panel.ActivityKey and panel:ActivityKey() or nil end,
        set = function(key) panel:PickActivity(key) end,
    })
    pick._activity:SetPoint("TOPRIGHT", pick, "TOPRIGHT", 0, 0)
    UI.ShadeField(pick._group)
    UI.ShadeField(pick._activity)
    pick._line = UI.PrimaryText(pick, "label")
    pick._line:SetPoint("LEFT", pick, "LEFT", 0, 0)
    pick._line:SetPoint("RIGHT", pick, "RIGHT", 0, 0)
    pick._line:SetWordWrap(false)
    pick._line:Hide()

    -- A caption over a hosted box
    local function Field(list, caption, height)
        local row = Row(list, L.captionHeight + L.captionGap + height)
        row._caption = UI.MakeCaption(row, caption)
        row._caption:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        local holder = CreateFrame("Frame", nil, row)
        Host.DressHolder(holder, UI.FieldFill())
        holder:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(L.captionHeight + L.captionGap))
        holder:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        row._holder = holder
        return row
    end
    panel._name = Field(panel._rows, Str("LFG_LIST_TITLE", "Title"), L.rowHeight)
    panel._details = Field(panel._left, Str("LFG_LIST_DETAILS", "Details"), detailsHeight)

    -- The playstyle, required
    local style = Row(panel._left, L.rowHeight)
    local P = Enum.LFGEntryGeneralPlaystyle
    local styleOrder = P and { P.Learning, P.FunRelaxed, P.FunSerious, P.Expert } or {}
    local styleValues = {}
    for _, v in ipairs(styleOrder) do styleValues[v] = GF.GeneralPlaystyleString(v) end
    style._dropdown = C:CreateDropdown({
        parent = style, width = half, height = L.rowHeight, values = styleValues, order = styleOrder,
        placeholder = Str("GROUP_FINDER_PLAYSTYLE_REQUIRED", "Playstyle"),
        get = function() return panel.Playstyle and panel:Playstyle() or nil end,
        set = function(v) panel:PickPlaystyle(v) end,
    })
    style._dropdown:SetPoint("TOPLEFT", style, "TOPLEFT", 0, 0)
    UI.ShadeField(style._dropdown)
    panel._style = style

    -- A requirement: the label, and an input or the hosted voice box at the
    -- right. The input stands inset in from the row's edge, since its border
    -- sits outside the box, so the voice holder and the inputs end level.
    local function Requirement(withInput)
        local row = Row(panel._right, L.rowHeight, L.rowGap)
        row._label = UI.PrimaryText(row, "desc")
        row._label:SetPoint("LEFT", row, "LEFT", 0, 0)
        row._label:SetWordWrap(false)
        if withInput then
            row._input = C.CreateNumericInput(row, {
                width = L.fieldWidth, height = L.inputHeight, inset = L.inputInset, fontSize = L.inputFont,
                min = 0, max = L.inputMax,
                onChange = function() panel:RefreshValid() end,
            })
            row._input:SetPoint("RIGHT", row, "RIGHT", -L.inputInset, 0)
            UI.ShadeField(row._input)
            -- A zero is no requirement: the box stays empty for it
            row._input:HookScript("OnEditFocusLost", function(input)
                if input:GetValue() == 0 then input:SetText("") end
            end)
            row._label:SetPoint("RIGHT", row._input, "LEFT", -L.gap, 0)
        else
            local holder = CreateFrame("Frame", nil, row)
            Host.DressHolder(holder, UI.FieldFill())
            holder:SetSize(L.fieldWidth + 2 * L.inputInset, L.inputHeight + 2 * L.inputInset)
            holder:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row._holder = holder
            row._label:SetPoint("RIGHT", holder, "LEFT", -L.gap, 0)
        end
        return row
    end
    panel._rating = Requirement(true)
    panel._level = Requirement(true)
    panel._voice = Requirement(false)
    panel._voice._label:SetText(Str("LFG_LIST_VOICE_CHAT", "Voice chat"))

    -- The two options under the requirements, a row each: own faction
    -- only, and private, the label where a requirement's is and the check
    -- at the right edge the fields end on
    local function Option()
        local row = Row(panel._right, L.rowHeight, L.rowGap)
        local check = C.CreateCheckBox(row, { clickable = true, onClick = function(self) panel:ToggleOption(self) end })
        check:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        local label = UI.PrimaryText(row, "desc")
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetPoint("RIGHT", check, "LEFT", -L.gap, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        check._label = label
        check._row = row
        return check
    end
    local options = { _cross = Option(), _private = Option() }
    options._private._label:SetText(Str("LFG_LIST_PRIVATE", "Private group"))
    panel._options = options

    -- The bottom edge: Back, and List Group with its reason in the tooltip
    panel._back = UI.MakeButton(panel, Str("BACK", "Back"), function() panel:Back() end, LAYOUT.buttonWidth)
    panel._back:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LAYOUT.panel.buttonX, LAYOUT.panel.buttonY)
    panel._list = UI.MakeButton(panel, Str("LIST_GROUP", "List Group"), function() panel:ListGroup() end,
        LAYOUT.buttonWidth, function() return panel._reason end)
    panel._list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LAYOUT.panel.buttonX, LAYOUT.panel.buttonY)
    panel._leaver = C.CreateTag(panel, { text = "LEAVER", tone = "dim" })
    panel._leaver:SetPoint("RIGHT", panel._list, "LEFT", -6, 0)
    panel._leaver:Hide()

    -- The busy cover while the client lists the group
    local cover = CreateFrame("Frame", nil, box)
    cover:SetAllPoints(box)
    cover:SetFrameLevel(box:GetFrameLevel() + 30)
    cover:EnableMouse(true)
    C.AddBackground(cover, { color = "collapsible" })
    cover:SetAlpha(L.coverAlpha)
    cover._empty = C.CreateEmptyState({ parent = cover, text = "" })
    cover._empty:SetAllPoints(cover)
    cover:Hide()
    panel._cover = cover

    -- The finder: every activity of the category or of a group, narrowed
    -- by the list's own box
    panel._finderKeys, panel._finderLabels = {}, {}
    panel._finder = C.CreatePopupList({
        anchor = pick._group,
        width = formWidth,
        filter = true,
        maxRows = L.finderRows,
        fontSize = LAYOUT.search.filterListFont,
        getKeys = function() return panel._finderKeys end,
        getValues = function() return panel._finderLabels end,
        getSelectedKey = function()
            local ec = EC()
            return ec and GF.plainNumber(ec.selectedActivity) or nil
        end,
        onSelect = function(id) panel:PickFinder(id) end,
    })

    ----------------------------------------------------------------------------
    -- Layout and mode
    ----------------------------------------------------------------------------

    -- A list's shown rows one under the other from y, x in and width wide;
    -- returns the y under the last
    local function Stack(rows, x, width, y)
        for _, row in ipairs(rows) do
            if row:IsShown() then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", form, "TOPLEFT", x, -y)
                row:SetWidth(width)
                y = y + row:GetHeight() + row._gap
            end
        end
        return y
    end

    -- The rows across the width, then the two columns side by side under them
    function panel:Flow()
        local y = Stack(self._rows, 0, formWidth, 0) + L.columnTop
        Stack(self._left, 0, half, y)
        Stack(self._right, rightX, rightWidth, y)
    end

    function panel:IsEditing()
        return UI.editing and true or false
    end

    function panel:Entry()
        if not self:IsEditing() then return nil end
        self._entry = self._entry or GF.ActiveEntry()
        return self._entry
    end

    -- The activity the form is about: the listing's while editing, else
    -- the hidden panel's choice
    function panel:ActivityID()
        if self:IsEditing() then
            local entry = self:Entry()
            local ids = entry and GF.plain(entry.activityIDs)
            return type(ids) == "table" and GF.plainNumber(ids[1]) or nil
        end
        local ec = EC()
        return ec and GF.plainNumber(ec.selectedActivity) or nil
    end

    ----------------------------------------------------------------------------
    -- The dropdowns
    ----------------------------------------------------------------------------

    -- The group dropdown shows the group, or the activity when it has no
    -- group, as Blizzard's shows it
    function panel:GroupKey()
        local ec = EC()
        if not ec then return nil end
        local groupID = GF.plainNumber(ec.selectedGroup)
        local activityID = GF.plainNumber(ec.selectedActivity)
        if groupID and GroupInfo(groupID) then return GROUP_PREFIX .. groupID end
        if activityID then return ACTIVITY_PREFIX .. activityID end
        return nil
    end

    function panel:GroupLabel()
        local ec = EC()
        if not ec then return nil end
        local name = GroupInfo(GF.plainNumber(ec.selectedGroup))
        if name then return name end
        local info = GF.ActivityInfo(GF.plainNumber(ec.selectedActivity))
        local short = info and GF.plain(info.shortName)
        return type(short) == "string" and short or nil
    end

    function panel:ActivityKey()
        local ec = EC()
        local activityID = ec and GF.plainNumber(ec.selectedActivity)
        return activityID and (ACTIVITY_PREFIX .. activityID) or nil
    end

    function panel:ActivityLabel()
        local info = GF.ActivityInfo(self:ActivityID())
        local short = info and GF.plain(info.shortName)
        return type(short) == "string" and short or nil
    end

    -- The groups and the group-less activities of the category merged by
    -- their order, the recommended ones alone past a few, and More past
    -- the cap, as Blizzard's menu lists them
    function panel:GroupOptions(categoryID, filters, selectedFilters)
        local values, order = {}, {}
        local F = Enum.LFGListFilter
        local groups = Activities(C_LFGList.GetAvailableActivityGroups, categoryID, filters)
        local activities = Activities(C_LFGList.GetAvailableActivities, categoryID, 0, filters)
        local useMore = false
        if selectedFilters == 0 and F and #groups + #activities > BLIZZARD.fewEntries then
            local rec = bit.bor(filters, F.Recommended)
            local recGroups = Activities(C_LFGList.GetAvailableActivityGroups, categoryID, rec)
            local recActivities = Activities(C_LFGList.GetAvailableActivities, categoryID, 0, rec)
            if #recGroups + #recActivities > 0 then
                useMore = #recGroups ~= #groups or #recActivities ~= #activities
                groups, activities = recGroups, recActivities
            end
        end
        local cap = MAX_LFG_LIST_GROUP_DROPDOWN_ENTRIES or BLIZZARD.dropdownCap
        local gi, ai = 1, 1
        local function GroupOrder()
            local _, orderIndex = GroupInfo(groups[gi])
            return groups[gi] and orderIndex or nil
        end
        local function ActivityOrder()
            local info = activities[ai] and GF.ActivityInfo(activities[ai])
            return info and GF.plainNumber(info.orderIndex) or nil
        end
        for _ = 1, cap do
            local go, ao = GroupOrder(), ActivityOrder()
            if not go and not ao then break end
            if ao and (not go or ao < go) then
                local id = activities[ai]
                local info = GF.ActivityInfo(id)
                local short = info and GF.plain(info.shortName)
                local key = ACTIVITY_PREFIX .. id
                values[key] = type(short) == "string" and short or tostring(id)
                order[#order + 1] = key
                ai = ai + 1
            else
                local id = groups[gi]
                local key = GROUP_PREFIX .. id
                values[key] = GroupInfo(id) or tostring(id)
                order[#order + 1] = key
                gi = gi + 1
            end
        end
        if #activities + #groups > cap then useMore = true end
        if useMore then
            values[MORE] = Str("LFG_LIST_MORE", "More")
            order[#order + 1] = MORE
        end
        return values, order
    end

    -- The group's activities, the recommended ones alone past a few
    function panel:ActivityOptions(categoryID, groupID, filters, selectedFilters)
        local values, order = {}, {}
        local F = Enum.LFGListFilter
        local activities = Activities(C_LFGList.GetAvailableActivities, categoryID, groupID, filters)
        local useMore = selectedFilters == 0
        if useMore and F then
            if #activities > BLIZZARD.fewEntries then
                local rec = Activities(C_LFGList.GetAvailableActivities, categoryID, groupID, bit.bor(filters, F.Recommended))
                useMore = #rec ~= #activities
                if #rec > 0 then
                    activities = rec
                else
                    for i = #activities, BLIZZARD.fewEntries, -1 do activities[i] = nil end
                end
            else
                useMore = false
            end
        end
        for _, id in ipairs(activities) do
            local info = GF.ActivityInfo(id)
            local short = info and GF.plain(info.shortName)
            local key = ACTIVITY_PREFIX .. id
            values[key] = type(short) == "string" and short or tostring(id)
            order[#order + 1] = key
        end
        if useMore then
            values[MORE] = Str("LFG_LIST_MORE", "More")
            order[#order + 1] = MORE
        end
        return values, order
    end

    function panel:RefreshDropdowns()
        local ec = EC()
        local editing = self:IsEditing()
        pick._line:SetShown(editing)
        if editing then
            pick._group:Hide()
            pick._activity:Hide()
            local activityID = self:ActivityID()
            local ok, name = false, nil
            if activityID then ok, name = pcall(C_LFGList.GetActivityFullName, activityID) end
            pick._line:SetText((ok and type(name) == "string") and name or "")
            pick:Show()
            return
        end
        local showGroup = ec and ec.GroupDropdown and ec.GroupDropdown:IsShown() or false
        local showActivity = ec and ec.ActivityDropdown and ec.ActivityDropdown:IsShown() or false
        pick._group:SetShown(showGroup)
        pick._activity:SetShown(showActivity)
        pick:SetShown(showGroup or showActivity)
        local categoryID = ec and GF.plainNumber(ec.selectedCategory)
        if not categoryID then return end
        local selectedFilters = GF.plainNumber(ec.selectedFilters) or 0
        local filters = bit.bor(GF.plainNumber(ec.baseFilters) or 0, selectedFilters)
        if showGroup then
            local values, order = self:GroupOptions(categoryID, filters, selectedFilters)
            EnsureKey(values, order, self:GroupKey(), self:GroupLabel())
            pick._group:SetOptions(values, order)
            pick._group:Refresh()
        end
        if showActivity then
            local values, order = self:ActivityOptions(categoryID, GF.plainNumber(ec.selectedGroup), filters, selectedFilters)
            EnsureKey(values, order, self:ActivityKey(), self:ActivityLabel())
            pick._activity:SetOptions(values, order)
            pick._activity:Refresh()
        end
    end

    function panel:PickGroup(key)
        local ec = EC()
        if not (ec and LFGListEntryCreation_Select) then return end
        if key == MORE then
            pick._group:Refresh()
            self:OpenFinder(nil)
            return
        end
        local kind, id = ParseKey(key)
        if kind == "g" then
            LFGListEntryCreation_Select(ec, GF.plainNumber(ec.selectedFilters), GF.plainNumber(ec.selectedCategory), id)
        elseif kind == "a" then
            LFGListEntryCreation_Select(ec, nil, nil, nil, id)
        end
        self:Refresh()
    end

    function panel:PickActivity(key)
        local ec = EC()
        if not (ec and LFGListEntryCreation_Select) then return end
        if key == MORE then
            pick._activity:Refresh()
            self:OpenFinder(GF.plainNumber(ec.selectedGroup))
            return
        end
        local kind, id = ParseKey(key)
        if kind == "a" then
            LFGListEntryCreation_Select(ec, nil, nil, nil, id)
        end
        self:Refresh()
    end

    function panel:PickFinder(id)
        local ec = EC()
        if not (ec and LFGListEntryCreation_Select and GF.plainNumber(id)) then return end
        LFGListEntryCreation_Select(ec, nil, nil, nil, id)
        self:Refresh()
    end

    -- Every activity of the category, or of the group, by relevance; the
    -- list's own box narrows them
    function panel:OpenFinder(groupID)
        local ec = EC()
        local categoryID = ec and GF.plainNumber(ec.selectedCategory)
        if not categoryID then return end
        local filters = GF.ResolveCategoryFilters(categoryID,
            bit.bor(GF.plainNumber(ec.baseFilters) or 0, GF.plainNumber(ec.selectedFilters) or 0))
        local ids = Activities(C_LFGList.GetAvailableActivities, categoryID, groupID, filters)
        if LFGListUtil_SortActivitiesByRelevancy then LFGListUtil_SortActivitiesByRelevancy(ids) end
        local keys, labels = {}, {}
        for _, id in ipairs(ids) do
            local ok, name = pcall(C_LFGList.GetActivityFullName, id)
            keys[#keys + 1] = id
            labels[id] = (ok and type(name) == "string") and name or tostring(id)
        end
        self._finderKeys, self._finderLabels = keys, labels
        self._finder:Open()
    end

    ----------------------------------------------------------------------------
    -- The playstyle
    ----------------------------------------------------------------------------

    -- The hidden panel's choice, or this panel's own while editing; nil
    -- for none, which the dropdown shows as its placeholder
    function panel:Playstyle()
        local v
        if self:IsEditing() then
            v = self._playstyle
        else
            local ec = EC()
            v = ec and GF.plainNumber(ec.generalPlaystyle) or nil
        end
        if v == nil or (P and v == P.None) then return nil end
        return v
    end

    -- Blizzard's own handler re-titles a Mythic+ listing for the new
    -- playstyle; an edit keeps the title as it stands
    function panel:PickPlaystyle(v)
        if self:IsEditing() then
            self._playstyle = v
        else
            local ec = EC()
            if ec and LFGListEntryCreation_OnPlayStyleSelectedInternal then
                LFGListEntryCreation_OnPlayStyleSelectedInternal(ec, v)
            end
        end
        self:RefreshValid()
    end

    ----------------------------------------------------------------------------
    -- The boxes
    ----------------------------------------------------------------------------

    function panel:TakeBoxes()
        local ec = EC()
        if not ec then return end
        local textInset = (M().field or {}).textInset or 8
        local detailsPad = L.detailsPad
        if ec.Name then
            Host.Take("name", ec.Name, self._name._holder, {
                artKeys = BOX_ART, artFrames = LOCK_FRAMES, textInsets = { textInset, textInset, 0, 0 },
                instructionsInsets = { textInset, textInset, 0, 0 },
                fallbackPoints = { { "TOPLEFT", ec.NameLabel, "BOTTOMLEFT", 5, -5 } },
            })
        end
        if ec.Description then
            Host.Take("description", ec.Description, self._details._holder, {
                editBox = ec.Description.EditBox, artKeys = Host.SCROLL_BOX_ART, artFrames = LOCK_FRAMES,
                inset = { left = detailsPad, right = detailsPad, top = detailsPad, bottom = detailsPad },
                editBoxWidth = half - 2 * detailsPad - L.detailsInset,
                fallbackPoints = { { "TOPLEFT", ec.DescriptionLabel, "BOTTOMLEFT", 5, -10 } },
            })
        end
        local voice = ec.VoiceChat and ec.VoiceChat.EditBox
        if voice then
            Host.Take("voice", voice, self._voice._holder, {
                artKeys = BOX_ART, artFrames = LOCK_FRAMES,
                textInsets = { L.voiceInset, L.voiceInset, 0, 0 },
                instructionsInsets = { L.voiceInset, L.voiceInset, 0, 0 },
                fontSize = L.voiceFont,
                fallbackPoints = { { "RIGHT", ec.VoiceChat, "RIGHT", -5, 0 } },
            })
        end
        self:HookBoxes(ec)
    end

    -- The hooks go on once: the validity follows the title and the details,
    -- and Tab moves among the three hosted boxes
    -- after Blizzard's own handler has moved it into a box of the hidden
    -- panel
    function panel:HookBoxes(ec)
        if self._boxesHooked then return end
        local name = ec.Name
        local details = ec.Description and ec.Description.EditBox
        local voice = ec.VoiceChat and ec.VoiceChat.EditBox
        if not (name and details and voice) then return end
        self._boxesHooked = true
        local cycle = { { name, details }, { details, voice }, { voice, name } }
        for _, pair in ipairs(cycle) do
            pair[1]:HookScript("OnTabPressed", function()
                if panel:IsShown() then pair[2]:SetFocus() end
            end)
        end
        name:HookScript("OnTextChanged", function()
            if panel:IsShown() then panel:RefreshValid() end
        end)
        details:HookScript("OnTextChanged", function()
            if panel:IsShown() then panel:RefreshValid() end
        end)
    end

    function panel:NameText()
        local ec = EC()
        return string.match(BoxText(ec and ec.Name), "^%s*(.-)%s*$")
    end

    ----------------------------------------------------------------------------
    -- The requirements and the options
    ----------------------------------------------------------------------------

    local function SetRequirement(row, n)
        row._input:SetValue(n or 0)
        if row._input:GetValue() == 0 then row._input:SetText("") end
    end

    -- A check in the accent, or dim while it cannot change
    local function PaintCheck(check, inert)
        local r, g, b
        if inert then
            r, g, b = Theme():GetDimTextColor()
        else
            r, g, b = Theme():GetAccentColor()
        end
        check:SetColor(r, g, b, 1)
        local lr, lg, lb = Theme():GetPrimaryTextColor()
        if inert then lr, lg, lb = Theme():GetDimTextColor() end
        check._label:SetTextColor(lr, lg, lb, 1)
    end

    -- A value the player cannot meet draws dim
    local function PaintInput(row)
        local r, g, b
        if row._warn then
            r, g, b = Theme():GetDimTextColor()
        else
            r, g, b = Theme():GetPrimaryTextColor()
        end
        row._input:SetTextColor(r, g, b, 1)
    end

    function panel:ToggleOption(check)
        if check._inert then
            check:SetChecked(true)
            return
        end
        check:SetChecked(not check:IsChecked())
    end

    -- Which rows show, their labels, and on a fresh form their values: a
    -- new form starts empty, an edit from the listing
    function panel:RefreshRows()
        local ec = EC()
        local editing = self:IsEditing()
        local entry = self:Entry()
        local activity = GF.ActivityInfo(self:ActivityID())
        local pvp = activity ~= nil and GF.plainBool(activity.isPvpActivity) == true
        local mplus = activity ~= nil and GF.plainBool(activity.isMythicPlusActivity) == true
        local rated = activity ~= nil and GF.plainBool(activity.isRatedPvpActivity) == true
        self._kind = { pvp = pvp, mplus = mplus, rated = rated }

        local rating, level = self._rating, self._level
        rating:SetShown(mplus or rated)
        if mplus then
            rating._label:SetText(Str("GROUP_FINDER_MYTHIC_RATING_REQ_LABEL", "Mythic+ rating"))
        else
            rating._label:SetText(Str("GROUP_FINDER_PVP_RATING_REQ_LABEL", "PvP rating"))
        end
        if pvp then
            level._label:SetText(Str("LFG_LIST_ITEM_LEVEL_PVP", "PvP item level"))
        else
            level._label:SetText(Str("LFG_LIST_ITEM_LEVEL_REQ", "Item level"))
        end

        -- Own faction only: shown for a category that allows the other,
        -- forced on and inert for an activity that does not
        local showCross, inertCross
        if editing then
            local category = activity and C_LFGList.GetLfgCategoryInfo(GF.plainNumber(activity.categoryID))
            showCross = type(category) == "table" and GF.plainBool(category.allowCrossFaction) == true
            inertCross = showCross and GF.plainBool(activity.allowCrossFaction) ~= true
        else
            local blizzard = ec and ec.CrossFactionGroup
            showCross = blizzard ~= nil and blizzard:IsShown()
            inertCross = showCross and not (blizzard.CheckButton and blizzard.CheckButton:IsEnabled())
        end
        local cross, private = self._options._cross, self._options._private
        local _, faction = UnitFactionGroup("player")
        cross._label:SetText(string.format(Str("LFG_LIST_CROSS_FACTION", "%s only"), faction or ""))
        cross:SetShown(showCross)
        cross._label:SetShown(showCross)
        cross._row:SetShown(showCross)
        cross._inert = inertCross and true or false
        if inertCross then cross:SetChecked(true) end
        PaintCheck(cross, inertCross)
        PaintCheck(private, false)

        if Create._fresh then
            Create._fresh = false
            if editing and entry then
                local ratingValue
                if mplus then
                    ratingValue = GF.plainNumber(entry.requiredDungeonScore)
                else
                    ratingValue = GF.plainNumber(entry.requiredPvpRating)
                end
                SetRequirement(level, GF.plainNumber(entry.requiredItemLevel))
                SetRequirement(rating, ratingValue)
                private:SetChecked(GF.plainBool(entry.privateGroup) == true)
                if not inertCross then cross:SetChecked(GF.plainBool(entry.isCrossFactionListing) ~= true) end
                self._playstyle = GF.plainNumber(entry.generalPlaystyle)
                -- A quest's listing keeps its title
                if ec and ec.Name and GF.plainNumber(entry.questID) then ec.Name:SetEnabled(false) end
            else
                SetRequirement(level, 0)
                SetRequirement(rating, 0)
                private:SetChecked(false)
                if not inertCross then cross:SetChecked(false) end
            end
        end
        self._style._dropdown:Refresh()
        if editing then
            self._list:SetText(Str("DONE_EDITING", "Done Editing"))
        else
            self._list:SetText(Str("LIST_GROUP", "List Group"))
        end
    end

    ----------------------------------------------------------------------------
    -- The valid state: Blizzard's reasons in its order, over this panel's
    -- values, in the button's tooltip
    ----------------------------------------------------------------------------

    function panel:RequirementWarning(activityID, kind)
        local level, rating = self._level, self._rating
        level._warn, rating._warn = false, false
        local warning
        local levelValue = level._input:GetValue() or 0
        if levelValue > 0 then
            local average, _, averagePvp = GetAverageItemLevel()
            if kind.pvp and levelValue > (averagePvp or 0) then
                warning = Str("LFG_LIST_PVP_ILVL_ABOVE_YOURS", "That PvP item level is above yours")
            elseif not kind.pvp and levelValue > (average or 0) then
                warning = Str("LFG_LIST_ILVL_ABOVE_YOURS", "That item level is above yours")
            end
            level._warn = warning ~= nil
        end
        if not warning and rating:IsShown() then
            local ratingValue = rating._input:GetValue() or 0
            if ratingValue > 0 then
                if kind.mplus and C_LFGList.ValidateRequiredDungeonScore
                    and not C_LFGList.ValidateRequiredDungeonScore(ratingValue) then
                    warning = Str("LFG_LIST_DUNGEON_SCORE_ABOVE_YOURS", "That rating is above yours")
                elseif kind.rated and C_LFGList.ValidateRequiredPvpRatingForActivity
                    and not C_LFGList.ValidateRequiredPvpRatingForActivity(activityID, ratingValue) then
                    warning = Str("LFG_LIST_PVP_RATING_ABOVE_YOURS", "That rating is above yours")
                end
                rating._warn = warning ~= nil
            end
        end
        PaintInput(level)
        PaintInput(rating)
        return warning
    end

    function panel:CensorBlock()
        if not (C_LFGList.IsCensoredActiveEntryUnresolved and C_LFGList.IsCensoredActiveEntryUnresolved()) then
            return nil
        end
        local ec = EC()
        if not (ec and C_LFGList.DoesCensoredTextMatch) then return nil end
        local ok, same = pcall(C_LFGList.DoesCensoredTextMatch, BoxText(ec.Name),
            BoxText(ec.Description and ec.Description.EditBox))
        if ok and same == true then return Str("CENSORED_LFG_EDIT_UNCHANGED", "Change the censored text") end
        return nil
    end

    function panel:RefreshValid()
        local activityID = self:ActivityID()
        local activity = GF.ActivityInfo(activityID)
        local kind = self._kind or {}
        local reason, blocked
        if not activity then
            blocked = true
        else
            local max = GF.plainNumber(activity.maxNumPlayers) or 0
            local categoryID = GF.plainNumber(activity.categoryID)
            local authenticated = C_LFGList.IsPlayerAuthenticatedForLFG
                and C_LFGList.IsPlayerAuthenticatedForLFG(categoryID)
            local keystone = C_LFGList.GetKeystoneForActivity and C_LFGList.GetKeystoneForActivity(activityID)
            local mplusBlock = not authenticated and kind.mplus and not keystone
            if max > 0 and GetNumGroupMembers(LE_PARTY_CATEGORY_HOME) >= max then
                reason = string.format(Str("LFG_LIST_TOO_MANY_FOR_ACTIVITY", "Too many members for this activity (%d)"), max)
            elseif self:Playstyle() == nil then
                reason = Str("GROUP_FINDER_PLAYSTYLE_REQUIRED", "Choose a playstyle")
            elseif mplusBlock then
                reason = Str("LFG_AUTHENTICATOR_BUTTON_MYTHIC_PLUS_TOOLTIP", "An authenticator is needed")
            elseif self:NameText() == "" then
                reason = Str("LFG_LIST_MUST_HAVE_NAME", "Enter a title")
            else
                reason = self:RequirementWarning(activityID, kind) or self:CensorBlock()
                    or (LFGListUtil_GetActiveQueueMessage and LFGListUtil_GetActiveQueueMessage(false)) or nil
            end
            blocked = reason ~= nil or mplusBlock
        end
        -- The leaver's flag is said, not blocking
        local leaver = kind.mplus and C_InstanceLeaver and C_InstanceLeaver.IsPlayerLeaver
            and C_InstanceLeaver.IsPlayerLeaver()
        self._leaver:SetShown(leaver and true or false)
        if leaver then
            local flagged = Str("MYTHIC_PLUS_DESERTER_FLAGGED_SHORT", "Flagged as a leaver")
            reason = reason and (reason .. "|n|n" .. flagged) or flagged
        end
        self._reason = reason
        self._list:SetEnabled(not blocked and not self._listing)
    end

    ----------------------------------------------------------------------------
    -- List Group, Done Editing, Back
    ----------------------------------------------------------------------------

    function panel:IsCrossFaction()
        local cross = self._options._cross
        return cross:IsShown() and not cross:IsChecked()
    end

    -- The listing as Blizzard's button assembles it; the title, the details
    -- and the voice chat the client reads from the hosted boxes
    function panel:ListGroup()
        if self._listing then return end
        local activityID = self:ActivityID()
        if not activityID then return end
        local kind = self._kind or {}
        local ratingValue = self._rating:IsShown() and (self._rating._input:GetValue() or 0) or 0
        local data = {
            activityIDs = { activityID },
            questID = 0,
            isAutoAccept = false,
            isCrossFactionListing = self:IsCrossFaction(),
            isPrivateGroup = self._options._private:IsChecked(),
            playstyle = Enum.LFGEntryPlaystyle and Enum.LFGEntryPlaystyle.None or 0,
            generalPlaystyle = self:Playstyle(),
            requiredDungeonScore = kind.mplus and ratingValue or 0,
            requiredItemLevel = self._level._input:GetValue() or 0,
            requiredPvpRating = kind.rated and ratingValue or 0,
        }
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if self:IsEditing() then
            local entry = self:Entry()
            if not entry then return end
            local ids = GF.plain(entry.activityIDs)
            if type(ids) == "table" then data.activityIDs = { GF.plainNumber(ids[1]) or activityID } end
            data.isAutoAccept = GF.plainBool(entry.autoAccept) == true
            data.questID = GF.plainNumber(entry.questID)
            -- A listing cannot change faction in place: it goes up again
            if (GF.plainBool(entry.isCrossFactionListing) == true) == data.isCrossFactionListing then
                C_LFGList.UpdateListing(data)
            else
                C_LFGList.RemoveListing()
                C_LFGList.CreateListing(data)
            end
            return
        end
        local ok, created = pcall(C_LFGList.CreateListing, data)
        if ok and created then
            if LFGListEntryCreation_ClearFocus and EC() then LFGListEntryCreation_ClearFocus(EC()) end
            self:SetBusy(true)
        end
    end

    function panel:SetBusy(on)
        self._listing = on and true or false
        self._cover:SetShown(self._listing)
        self._cover._empty:SetBusy(self._listing, Str("LFG_LIST_CREATING_ENTRY", "Creating listing"))
        self:RefreshValid()
    end

    -- Back ends the view, and the window shows Blizzard's active panel
    -- again: the categories, or the viewer after an edit
    function panel:Back()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Create:Close()
        UI:SetView(nil)
    end

    ----------------------------------------------------------------------------
    -- Refresh
    ----------------------------------------------------------------------------

    function panel:RefreshHeading()
        local ec = EC()
        local activity = GF.ActivityInfo(self:ActivityID())
        local categoryID = activity and GF.plainNumber(activity.categoryID)
            or (ec and GF.plainNumber(ec.selectedCategory))
        local info = categoryID and C_LFGList.GetLfgCategoryInfo(categoryID)
        local name = type(info) == "table" and GF.plain(info.name)
        if type(name) ~= "string" then name = Str("START_A_GROUP", "Start a Group") end
        self._heading:SetText(name)
    end

    function panel:Refresh()
        if not EC() then return end
        self._entry = nil
        self:RefreshHeading()
        self:TakeBoxes()
        self:RefreshDropdowns()
        self:RefreshRows()
        self:Flow()
        self:RefreshValid()
    end

    function panel:Cleanup()
        self._finder:Destroy()
        pick._group:Cleanup()
        pick._activity:Cleanup()
        style._dropdown:Cleanup()
    end

    panel:HookScript("OnHide", function()
        panel._finder:Close()
        panel._cover:Hide()
        panel._listing = false
    end)

    -- The listing's update ends an edit (a listing going up switches
    -- Blizzard's panel, which ends the view on its own); a listing going
    -- up, or failing to, lifts the cover
    GF.Listen("entry", function()
        if UI.editing then
            Create:Close()
            UI:SyncPanel()
        end
        if panel:IsShown() then panel:SetBusy(false) end
    end)
    GF.Listen("creationFailed", function()
        if panel:IsShown() then panel:SetBusy(false) end
    end)
    GF.Listen("buttons", function()
        if panel:IsShown() then panel:RefreshValid() end
    end)

    return panel
end

UI.panelBuilders.create = Build
