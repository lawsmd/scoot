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
-- writes the client's advanced or language filter and redraws the rows.
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

-- Dungeons search the current expansion's activities only
local function ResolveFilters(categoryID, filters)
    local F = Enum.LFGListFilter
    if categoryID == GF.DUNGEONS_CATEGORY and F then
        return bit.band(bit.bnot(F.NotRecommended), bit.bor(filters, F.Recommended))
    end
    return filters
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

local function CreateRow(row)
    local C = Controls()
    local L = LAYOUT.search
    local padX = (M().listRow or {}).padX or 8

    row._name = UI.PrimaryText(row, "label")
    row._name:SetPoint("TOPLEFT", row, "TOPLEFT", padX, -L.nameTop)
    row._name:SetPoint("RIGHT", row, "RIGHT", -(padX + L.rightColumn), 0)
    row._name:SetWordWrap(false)

    row._activity = UI.DimText(row, "desc")
    row._activity:SetPoint("TOPLEFT", row._name, "BOTTOMLEFT", 0, -1)
    row._activity:SetPoint("RIGHT", row._name, "RIGHT", 0, 0)
    row._activity:SetWordWrap(false)

    row._playstyle = UI.DimText(row, "desc")
    row._playstyle:SetPoint("TOPLEFT", row._activity, "BOTTOMLEFT", 0, -1)
    row._playstyle:SetPoint("RIGHT", row._name, "RIGHT", 0, 0)
    row._playstyle:SetWordWrap(false)
    local lr, lg, lb = Theme():GetDimTextLightColor()
    row._playstyle:SetTextColor(lr, lg, lb, 1)

    row._marks = C.CreateRoleMarks(row, { size = 11 })
    row._marks:SetPoint("RIGHT", row, "RIGHT", -padX, 0)

    row._count = UI.DimText(row, "miniLabel")
    row._count:SetPoint("RIGHT", row, "RIGHT", -padX, 0)
    row._count:SetJustifyH("RIGHT")

    row._voice = C.CreateTag(row, { text = "VOICE", tone = "dim" })
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

-- The group's composition, by the activity's display type: marks for a
-- small group, a count line for a large one
local function RenderComposition(row, info, counts, dimmed)
    local activity = GF.ActivityInfo(GF.ActivityID(info))
    row._marks:Hide()
    row._count:Hide()
    if not activity or not counts then return end
    local D = Enum.LFGListDisplayType
    local kind = activity.displayType
    local tank = GF.plainNumber(counts.TANK) or 0
    local healer = GF.plainNumber(counts.HEALER) or 0
    local damage = GF.plainNumber(counts.DAMAGER) or 0

    if D and (kind == D.RoleEnumerate or kind == D.ClassEnumerate) then
        local max = GF.plainNumber(activity.maxNumPlayers) or 5
        if max > 8 then
            row._count:SetText(string.format("%d T  %d H  %d D", tank, healer, damage))
            row._count:Show()
            return
        end
        local byClass = SelectedCategory() == GF.DUNGEONS_CATEGORY and type(counts.classesByRole) == "table"
        local slots = {}
        for _, role in ipairs(ROLE_ORDER) do
            local classes = byClass and counts.classesByRole[role]
            if type(classes) == "table" then
                for class, num in pairs(classes) do
                    local cr, cg, cb = addon.GetClassColorRGB(class)
                    for _ = 1, (GF.plainNumber(num) or 0) do
                        slots[#slots + 1] = { role = role, filled = true, color = cr and { cr, cg, cb } or nil }
                    end
                end
            else
                for _ = 1, (GF.plainNumber(counts[role]) or 0) do
                    slots[#slots + 1] = { role = role, filled = true }
                end
            end
        end
        -- The open slots, by the role still wanted
        for _, role in ipairs(ROLE_ORDER) do
            for _ = 1, (GF.plainNumber(counts[role .. "_REMAINING"]) or 0) do
                if #slots >= max then break end
                slots[#slots + 1] = { role = role, filled = false }
            end
        end
        while #slots > max do table.remove(slots) end
        row._marks:SetSlots(slots)
        row._marks:SetAlpha(dimmed and 0.5 or 1)
        row._marks:Show()
    elseif D and kind == D.RoleCount then
        row._count:SetText(string.format("%d T  %d H  %d D", tank, healer, damage))
        row._count:Show()
    elseif D and kind == D.PlayerCount then
        local total = tank + healer + damage + (GF.plainNumber(counts.NOROLE) or 0)
        row._count:SetText(string.format("%d/%d", total, GF.plainNumber(activity.maxNumPlayers) or total))
        row._count:Show()
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
    theme:ApplyFont(row._activity, "desc")
    theme:ApplyFont(row._playstyle, "desc")
    theme:ApplyFont(row._count, "miniLabel")
    theme:ApplyFont(row._timer, "miniLabel")

    local info = GF.ResultInfo(id)
    if not info then
        row._name:SetText("")
        row._activity:SetText("")
        row._playstyle:SetText("")
        row._marks:Hide()
        row._count:Hide()
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
        row._marks:Hide()
        row._count:Hide()
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
        right = right - (row._status:GetWidth() or 40) - 4
    else
        row._status:Hide()
        row._timer:Hide()
        row._cancel:Hide()
        RenderComposition(row, info, counts, dimmed)
        local shown = row._marks:IsShown() and row._marks or (row._count:IsShown() and row._count) or nil
        if shown then
            right = right - (shown:GetWidth() or 0) - 6
        end
    end

    if NonEmpty(info.voiceChat) then
        row._voice:ClearAllPoints()
        row._voice:SetPoint("RIGHT", row, "RIGHT", right, 0)
        row._voice:Show()
    else
        row._voice:Hide()
    end

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
    local boxX = LAYOUT.panel.boxX
    local pad = (M().collapsible or {}).contentPadding or 12

    -- The category's name, and the filter list's button at the row's right
    panel._heading = UI.MakeHeading(panel, "")
    panel._heading:SetPoint("RIGHT", panel, "RIGHT", -boxX, 0)
    panel._heading:SetWordWrap(false)

    panel._filter = UI.MakeButton(panel, Str("FILTER", "Filter"), function() panel:OpenFilter() end, L.filterWidth)
    panel._filter:SetHeight(L.rowHeight)
    panel._filter:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -boxX, -L.rowY)

    -- The circled asterisk is the one refresh-like mark the mono face carries;
    -- the circle arrows are not in its tables
    panel._refresh = UI.MakeButton(panel, "\226\138\155", function() panel:Search() end, L.rowHeight)
    panel._refresh:SetHeight(L.rowHeight)
    panel._refresh:HookScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText(Str("LFG_LIST_SEARCH_AGAIN", "Search again"))
        GameTooltip:Show()
    end)
    panel._refresh:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- The hosted box's holder, and the x over Blizzard's clear button
    local holder = CreateFrame("Frame", nil, panel)
    Host.DressHolder(holder)
    holder:SetHeight(L.rowHeight)
    holder:SetPoint("TOPLEFT", panel, "TOPLEFT", boxX, -L.rowY)
    holder:SetPoint("RIGHT", panel._refresh, "LEFT", -L.gap, 0)
    panel._holder = holder
    panel._clear = UI.AccentText(holder, "label")
    panel._clear:SetText("x")
    panel._clear:Hide()

    -- The results
    local box = UI.MakeBox(panel, L.boxTop)
    panel._box = box
    local list = C.CreateScrollList({
        parent = box,
        rowHeight = LAYOUT.Template("LFGListSearchEntryTemplate", "resultRow"),
        rowGap = 2,
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

    -- The bottom edge
    panel._note = UI.MakeNote(panel)

    panel._back = UI.MakeButton(panel, Str("BACK", "Back"), function() panel:Back() end, LAYOUT.buttonWidth)
    panel._back:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LAYOUT.panel.buttonX, LAYOUT.panel.buttonY)

    panel._signUp = UI.MakeButton(panel, Str("SIGN_UP", "Sign Up"), function() panel:SignUp() end, LAYOUT.buttonWidth)
    panel._signUp:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LAYOUT.panel.buttonX, LAYOUT.panel.buttonY)

    panel._leaver = C.CreateTag(panel, { text = "LEAVER", tone = "dim" })
    panel._leaver:SetPoint("RIGHT", panel._signUp, "LEFT", -6, 0)
    panel._leaver:Hide()

    -- The lists that float: the filter, the auto-complete, the row menu
    panel._filterMode = "languages"
    panel._filterList = C.CreatePopupList({
        anchor = panel._filter,
        width = 220,
        multiSelect = true,
        getKeys = function() return panel:FilterKeys() end,
        getValues = function() return panel._filterLabels or {} end,
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
        if editBox.clearButton then
            self._clear:ClearAllPoints()
            self._clear:SetPoint("CENTER", editBox.clearButton, "CENTER", 0, 0)
            self._clear:SetShown(editBox.clearButton:IsShown())
        end
        if self._boxHooked then return end
        self._boxHooked = true
        editBox:HookScript("OnTextChanged", function()
            if editBox.clearButton then self._clear:SetShown(editBox.clearButton:IsShown()) end
            self:RefreshAuto()
        end)
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
        local filters = ResolveFilters(categoryID, GF.plainNumber(sp.filters) or 0)
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
        GF.NoteSearch()
        LFGListSearchPanel_DoSearch(sp)
        if sp.SearchBox then sp.SearchBox:ClearFocus() end
    end

    ----------------------------------------------------------------------------
    -- Searching
    ----------------------------------------------------------------------------

    function panel:Search()
        local sp = SearchPanel()
        if not (sp and LFGListSearchPanel_DoSearch) then return end
        if not GF.SearchAllowed() then
            self:RefreshButtons()
            return
        end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        GF.NoteSearch()
        LFGListSearchPanel_DoSearch(sp)
    end

    function panel:Back()
        if not (LFGListFrame and LFGListFrame_SetActivePanel) then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        GF.state.selectedResult = nil
        LFGListFrame_SetActivePanel(LFGListFrame, LFGListFrame.CategorySelection)
    end

    function panel:SignUp()
        local id = GF.state.selectedResult
        if not id or GF.SignUpBlock() then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        UI.SignUp:Show(id)
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

    local ADVANCED = {
        { key = "needsTank", label = "LFG_LIST_NEEDS_TANK", role = 1 },
        { key = "needsHealer", label = "LFG_LIST_NEEDS_HEALER", role = 2 },
        { key = "needsDamage", label = "LFG_LIST_NEEDS_DAMAGE", role = 3 },
        { key = "needsMyClass", label = "LFG_LIST_CLASS_AVAILABLE", class = true },
        { key = "hasTank", label = "LFG_LIST_HAS_TANK" },
        { key = "hasHealer", label = "LFG_LIST_HAS_HEALER" },
        { key = "difficultyNormal", label = "PLAYER_DIFFICULTY1" },
        { key = "difficultyHeroic", label = "PLAYER_DIFFICULTY2" },
        { key = "difficultyMythic", label = "PLAYER_DIFFICULTY6" },
        { key = "difficultyMythicPlus", label = "PLAYER_DIFFICULTY_MYTHIC_PLUS" },
        { key = "generalPlaystyle1", label = "GROUP_FINDER_GENERAL_PLAYSTYLE1" },
        { key = "generalPlaystyle2", label = "GROUP_FINDER_GENERAL_PLAYSTYLE2" },
        { key = "generalPlaystyle3", label = "GROUP_FINDER_GENERAL_PLAYSTYLE3" },
        { key = "generalPlaystyle4", label = "GROUP_FINDER_GENERAL_PLAYSTYLE4" },
    }

    local function AtMaxLevel()
        return GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel and GameRulesUtil.IsPlayerAtEffectiveMaxLevel()
    end

    local function CanChangeLanguages()
        return LFGListCanChangeLanguages and LFGListCanChangeLanguages() or false
    end

    -- Dungeons at max level take the advanced filter; every other category
    -- the languages, as Blizzard's button decides
    function panel:FilterKeys()
        local keys, labels = {}, {}
        if SelectedCategory() == GF.DUNGEONS_CATEGORY and AtMaxLevel() then
            self._filterMode = "advanced"
            local tank, healer, dps = C_LFGList.GetAvailableRoles()
            local avail = { tank, healer, dps }
            for _, entry in ipairs(ADVANCED) do
                if not entry.role or avail[entry.role] then
                    keys[#keys + 1] = entry.key
                    local label = Str(entry.label, entry.key)
                    if entry.class and PlayerUtil and PlayerUtil.GetClassName then
                        label = string.format(label, PlayerUtil.GetClassName())
                    end
                    labels[entry.key] = label
                end
            end
        else
            self._filterMode = "languages"
            local languages = C_LFGList.GetAvailableLanguageSearchFilter and C_LFGList.GetAvailableLanguageSearchFilter() or {}
            for _, lang in ipairs(languages) do
                keys[#keys + 1] = lang
                labels[lang] = Str("LFG_LIST_LANGUAGE_" .. string.upper(lang), lang)
            end
        end
        self._filterLabels = labels
        return keys
    end

    function panel:FilterChecked(key)
        if self._filterMode == "advanced" then
            local enabled = C_LFGList.GetAdvancedFilter()
            return type(enabled) == "table" and enabled[key] == true
        end
        local enabled = C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter() or {}
        return enabled[key] == true
    end

    -- A default language stays on, as Blizzard's list has it
    function panel:FilterInert(key)
        if self._filterMode ~= "languages" then return false end
        local defaults = C_LFGList.GetDefaultLanguageSearchFilter and C_LFGList.GetDefaultLanguageSearchFilter() or {}
        return defaults[key] == true
    end

    function panel:FilterToggle(key, checked)
        if self._filterMode == "advanced" then
            local enabled = C_LFGList.GetAdvancedFilter()
            if type(enabled) ~= "table" then return end
            enabled[key] = checked and true or false
            C_LFGList.SaveAdvancedFilter(enabled)
            self._list:Refresh()
            return
        end
        if not C_LFGList.SaveLanguageSearchFilter then return end
        local enabled = C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter() or {}
        enabled[key] = checked and true or false
        C_LFGList.SaveLanguageSearchFilter(enabled)
    end

    function panel:OpenFilter()
        self._filterList:Toggle()
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
            local leader = SS.plainString(info.leaderName)
            if leader then GameTooltip:AddLine(leader) end
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

    function panel:RefreshList()
        local state = GF.state
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

        if state.searching then
            self._empty:SetBusy(true, Str("SEARCHING", "Searching"))
            self._empty:Show()
            self._list.frame:Hide()
        elseif state.searchFailed then
            local text = Str("LFG_LIST_SEARCH_FAILED", "Search failed")
            if state.failReason then text = text .. " (" .. tostring(state.failReason) .. ")" end
            self._empty:SetBusy(false, text)
            self._empty:Show()
            self._list.frame:Hide()
        elseif #items == 0 then
            self._empty:SetBusy(false, Str("LFG_LIST_NO_RESULTS_FOUND", "No groups found"))
            self._empty:Show()
            self._list.frame:Hide()
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
        local block = GF.SignUpBlock()
        self._signUp:SetEnabled(block == nil)
        local allowed = GF.SearchAllowed()
        self._refresh:SetEnabled(allowed)
        if not allowed then
            local left = GF.SearchCooldownLeft()
            block = block or string.format("Searching again in %d s", math.ceil(left))
            C_Timer.After(left + 0.05, function()
                if self:IsShown() then self:RefreshButtons() end
            end)
        end
        self._note:SetText(block or "")
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
        self._auto:Destroy()
        self._menu:Destroy()
    end

    panel:HookScript("OnHide", function()
        panel._auto:Close()
        panel._filterList:Close()
        panel._menu:Close()
        panel:StopTicker()
    end)

    GF.Listen("searching", function()
        if panel:IsShown() then
            panel:RefreshList()
            panel:RefreshButtons()
        end
    end)
    GF.Listen("results", function()
        if panel:IsShown() then
            panel:RefreshList()
            panel:RefreshButtons()
        end
    end)
    GF.Listen("failed", function()
        if panel:IsShown() then
            panel:RefreshList()
            panel:RefreshButtons()
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
