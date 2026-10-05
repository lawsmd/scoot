-- categories.lua - the Category selection panel: a row per category from
-- the client's list, Find Group and Start Group under it.
--
-- The rows are built as Blizzard builds its buttons: one per category, or
-- two for a category that separates the current expansion's activities from
-- the rest, each kept only when it has activities. A row click runs
-- Blizzard's own SelectCategory, so its hidden panel holds the selection,
-- and Find Group runs its StartFindGroup, which sets the search panel's
-- category, runs the search and makes the search panel active; the window
-- follows that switch. Start Group is drawn off until the listing panel
-- exists.
local addonName, addon = ...

local GF = addon.GroupFinder
local UI = GF.UI
local LAYOUT = UI.LAYOUT
local Str = GF.Str

local function Controls()
    return addon.UI.Controls
end

local function M()
    return addon.UI.Controls.Metrics()
end

local function CategoryPanel()
    return LFGListFrame and LFGListFrame.CategorySelection
end

--------------------------------------------------------------------------------
-- The rows
--------------------------------------------------------------------------------

local function AddItem(items, categoryID, filters, baseFilters, info)
    local all = bit.bor(baseFilters, filters)
    if filters ~= 0 then
        local activities = C_LFGList.GetAvailableActivities(categoryID, nil, all)
        if type(activities) ~= "table" or #activities == 0 then return end
    end
    local label = info.name
    if LFGListUtil_GetDecoratedCategoryName then
        label = LFGListUtil_GetDecoratedCategoryName(info.name, filters, false)
    end
    items[#items + 1] = { categoryID = categoryID, filters = filters, label = label }
end

local function Items()
    local items = {}
    local lf = LFGListFrame
    local baseFilters = lf and GF.plainNumber(lf.baseFilters) or 0
    local categories = C_LFGList.GetAvailableCategories(baseFilters)
    if type(categories) ~= "table" then return items end
    local recommended = Enum.LFGListFilter and Enum.LFGListFilter.Recommended or 1
    local notRecommended = Enum.LFGListFilter and Enum.LFGListFilter.NotRecommended or 2
    for _, categoryID in ipairs(categories) do
        local info = C_LFGList.GetLfgCategoryInfo(categoryID)
        if type(info) == "table" and type(info.name) == "string" then
            if info.separateRecommended then
                AddItem(items, categoryID, recommended, baseFilters, info)
                AddItem(items, categoryID, notRecommended, baseFilters, info)
            else
                AddItem(items, categoryID, 0, baseFilters, info)
            end
        end
    end
    return items
end

local function PaintRow(row)
    local r, g, b, a = row._backdrop:LabelColor()
    row._label:SetTextColor(r, g, b, a or 1)
end

local function CreateRow(row)
    local padX = (M().listRow or {}).padX or 8
    local label = row:CreateFontString(nil, "OVERLAY")
    addon.UI.Theme:ApplyFont(label, "label")
    label:SetPoint("LEFT", row, "LEFT", padX, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -padX, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row._label = label
end

local function RenderRow(row, item)
    addon.UI.Theme:ApplyFont(row._label, "label")
    row._label:SetText(item.label or "")
    PaintRow(row)
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

local function Build(parent)
    local panel = UI.MakePanel(parent)
    local C = Controls()
    local pad = (M().collapsible or {}).contentPadding or 12

    panel._heading = UI.MakeHeading(panel, Str("LFGLIST_NAME", "Premade Groups"))
    local box = UI.MakeBox(panel)
    panel._box = box

    local list = C.CreateScrollList({
        parent = box,
        rowHeight = LAYOUT.Template("LFGListCategoryTemplate", "categoryRow"),
        rowGap = 3,
        createRow = CreateRow,
        render = RenderRow,
        onSelect = function(item)
            local cs = CategoryPanel()
            if cs and LFGListCategorySelection_SelectCategory then
                LFGListCategorySelection_SelectCategory(cs, item.categoryID, item.filters)
            end
            panel:RefreshButtons()
        end,
        onEnter = function(_, _, row) PaintRow(row) end,
        onLeave = function(_, _, row) PaintRow(row) end,
    })
    list.frame:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -pad)
    list.frame:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -pad, pad)
    panel._list = list

    panel._note = UI.MakeNote(panel)

    panel._find = UI.MakeButton(panel, Str("LFG_LIST_FIND_A_GROUP", "Find a Group"), function()
        local cs = CategoryPanel()
        if not (cs and LFGListCategorySelection_StartFindGroup) then return end
        if not GF.SearchAllowed() then
            panel._note:SetText(string.format("Searching again in %d s", math.ceil(GF.SearchCooldownLeft())))
            return
        end
        GF.NoteSearch()
        LFGListCategorySelection_StartFindGroup(cs)
    end, LAYOUT.buttonWidth)
    panel._find:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LAYOUT.panel.buttonX, LAYOUT.panel.buttonY)

    panel._start = UI.MakeButton(panel, Str("START_A_GROUP", "Start a Group"), nil, LAYOUT.buttonWidth)
    panel._start:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LAYOUT.panel.buttonX, LAYOUT.panel.buttonY)
    panel._start:SetEnabled(false)

    -- The selection Blizzard's panel holds, found among the rows
    function panel:RefreshItems()
        local items = Items()
        self._list:SetItems(items)
        local cs = CategoryPanel()
        local selectedCategory = cs and GF.plainNumber(cs.selectedCategory)
        local selectedFilters = cs and GF.plainNumber(cs.selectedFilters)
        local index
        if selectedCategory then
            for i, item in ipairs(items) do
                if item.categoryID == selectedCategory and item.filters == selectedFilters then
                    index = i
                    break
                end
            end
        end
        self._list:SetSelected(index)
        for i = 1, #items do
            local row = self._list:GetRow(i)
            if row then PaintRow(row) end
        end
    end

    -- Find Group follows Blizzard's nav rules: a category, and an account
    -- that may speak. Start Group takes its rules with the listing panel.
    function panel:RefreshButtons()
        local cs = CategoryPanel()
        local selected = cs and GF.plainNumber(cs.selectedCategory)
        local findOn, note = true, nil
        if not selected then
            findOn = false
            note = Str("LFG_LIST_SELECT_A_CATEGORY", "Select a category")
        end
        if C_SocialRestrictions then
            if C_SocialRestrictions.IsSilenced and C_SocialRestrictions.IsSilenced() then
                findOn = false
                note = Str("ERR_ACCOUNT_SILENCED", "This account is silenced")
            elseif C_SocialRestrictions.IsSquelched and C_SocialRestrictions.IsSquelched() then
                findOn = false
                note = Str("ERR_USER_SQUELCHED", "This account is squelched")
            end
        end
        self._find:SetEnabled(findOn)
        self._start:SetEnabled(false)
        self._note:SetText(note or "")
    end

    function panel:Refresh()
        self:RefreshItems()
        self:RefreshButtons()
    end

    function panel:Cleanup()
        self._list:Cleanup()
    end

    GF.Listen("categories", function()
        if panel:IsShown() then panel:Refresh() end
    end)
    GF.Listen("buttons", function()
        if panel:IsShown() then panel:RefreshButtons() end
    end)

    return panel
end

UI.panelBuilders.categories = Build
