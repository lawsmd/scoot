-- categories.lua - the Category selection panel: a tree in the main
-- menu's nav look, the window's name at its root and a row per category
-- under it, centred in the window with Start Group and Find Group side by
-- side beneath.
--
-- The rows are built as Blizzard builds its buttons: one per category, or
-- two for a category that separates the current expansion's activities from
-- the rest, each kept only when it has activities. Each row hangs off the
-- tree's trunk on the nav's lines, and its name sits in a box as wide as
-- the name, which takes the hover and the selection (the listRow role's
-- washes and bar, without its rule). A row click runs Blizzard's own
-- SelectCategory, so its hidden panel holds the selection, and Find Group
-- opens the window's search view on the category (search.lua), which sets
-- Blizzard's search panel's category and runs the search without making
-- that panel active. Start Group opens the listing form on the category
-- (create.lua), off for the reason its tooltip gives.
local addonName, addon = ...

local GF = addon.GroupFinder
local UI = GF.UI
local LAYOUT = UI.LAYOUT
local Str = GF.Str

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

-- Where a row's box starts: past the branch where the skin draws the tree's
-- lines, else at the branch's end all the same
local function BoxLeft()
    local L = LAYOUT.categories
    return L.treeLineX + L.treeLineLength + 2
end

-- The trunk and the branch in the accent at the nav's line alpha
local function PaintLines(row)
    if not row._trunk then return end
    local ar, ag, ab = addon.UI.Theme:GetAccentColor()
    local alpha = M().nav.treeLineAlpha
    row._trunk:SetColorTexture(ar, ag, ab, alpha)
    row._branch:SetColorTexture(ar, ag, ab, alpha)
end

-- The trunk runs the row's full height, from the root's gap on the first
-- row, and stops at the branch on the last
local function PlaceTrunk(row, isFirst, isLast)
    local trunk = row._trunk
    if not trunk then return end
    local L = LAYOUT.categories
    trunk:ClearAllPoints()
    trunk:SetPoint("TOPLEFT", row, "TOPLEFT", L.treeLineX, isFirst and L.rootGap or 0)
    if isLast then
        trunk:SetPoint("BOTTOM", row, "LEFT", L.treeLineX, 0)
    else
        trunk:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", L.treeLineX, 0)
    end
end

local function CreateRow(stack, onClick)
    local nav = M().nav
    local L = LAYOUT.categories
    local row = CreateFrame("Frame", nil, stack)
    row:SetHeight(L.rowHeight)

    if nav.treeLineWidth > 0 then
        row._trunk = row:CreateTexture(nil, "ARTWORK")
        row._trunk:SetWidth(nav.treeLineWidth)
        row._branch = row:CreateTexture(nil, "ARTWORK")
        row._branch:SetHeight(nav.treeLineWidth)
        row._branch:SetWidth(L.treeLineLength - nav.treeLineWidth)
        row._branch:SetPoint("LEFT", row, "LEFT", L.treeLineX + nav.treeLineWidth, 0)
        PaintLines(row)
    end

    local box = CreateFrame("Button", nil, row)
    box:SetPoint("TOPLEFT", row, "TOPLEFT", BoxLeft(), 0)
    box:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", BoxLeft(), 0)
    box:SetWidth(L.boxPad * 2)
    box:RegisterForClicks("LeftButtonUp")
    row._box = box

    local label = box:CreateFontString(nil, "OVERLAY")
    addon.UI.Theme:ApplyFont(label, "label", L.labelSize)
    label:SetPoint("LEFT", box, "LEFT", L.boxPad, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row._label = label

    row._backdrop = addon.UI.Chrome.Backdrop("listRow", box, { label = label, rule = false })
    box:SetScript("OnEnter", function() row._backdrop:SetHover(true) end)
    box:SetScript("OnLeave", function() row._backdrop:SetHover(false) end)
    box:SetScript("OnClick", function() onClick(row._item) end)
    return row
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

local function Build(parent)
    local panel = UI.MakePanel(parent)
    local L = LAYOUT.categories

    -- The tree and the buttons under it, sized to its contents and centred
    local stack = CreateFrame("Frame", nil, panel)
    stack:SetPoint("CENTER", panel, "CENTER", 0, 0)
    panel._stack = stack

    local root = UI.AccentText(stack, "header", L.rootSize)
    root:SetPoint("TOPLEFT", stack, "TOPLEFT", 0, 0)
    root:SetText(UI.WINDOW_TITLE)
    root:SetWordWrap(false)
    panel._root = root

    local function SelectItem(item)
        if not item then return end
        local cs = CategoryPanel()
        if cs and LFGListCategorySelection_SelectCategory then
            LFGListCategorySelection_SelectCategory(cs, item.categoryID, item.filters)
        end
        panel:PaintSelection()
        panel:RefreshButtons()
    end

    panel._rows = addon.Pool.NewIndexed(function() return CreateRow(stack, SelectItem) end)
    panel._items = {}
    local buttonSize = { height = L.buttonHeight, fontSize = L.buttonFont }

    -- Find Group opens the search view, whose search the host's hook notes;
    -- inside the cooldown the click waits and the tooltip says for how long
    panel._find = UI.MakeButton(stack, Str("LFG_LIST_FIND_A_GROUP", "Find a Group"), function()
        local cs = CategoryPanel()
        local category = cs and GF.plainNumber(cs.selectedCategory)
        if not (category and UI.Search) then return end
        if not GF.SearchAllowed() then return end
        UI.Search:Open(category, GF.plainNumber(cs.selectedFilters) or 0)
    end, L.buttonWidth, function()
        if not GF.SearchAllowed() then
            return string.format("Searching again in %d s", math.ceil(GF.SearchCooldownLeft()))
        end
        return panel._findReason
    end, buttonSize)
    panel._find:SetPoint("BOTTOMLEFT", stack, "BOTTOM", L.buttonGap / 2, 0)

    panel._start = UI.MakeButton(stack, Str("START_A_GROUP", "Start a Group"), function()
        local cs = CategoryPanel()
        local category = cs and GF.plainNumber(cs.selectedCategory)
        if not (category and UI.Create) or GF.StartGroupBlock() then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        UI.Create:Open(category, GF.plainNumber(cs.selectedFilters) or 0)
    end, L.buttonWidth, function() return panel._startReason end, buttonSize)
    panel._start:SetPoint("BOTTOMRIGHT", stack, "BOTTOM", -L.buttonGap / 2, 0)

    -- Each box as wide as its name, and the stack as wide as the root or
    -- the widest box and as tall as the tree and the buttons. A name set
    -- this frame may measure short, so the caller runs this again a frame on
    function panel:Layout()
        local widest = root:GetStringWidth() or 0
        local boxLeft = BoxLeft()
        for i = 1, #self._items do
            local row = self._rows:Get(i)
            local width = (row._label:GetStringWidth() or 0) + L.boxPad * 2
            row._box:SetWidth(width)
            widest = math.max(widest, boxLeft + width)
        end
        local rootHeight = math.max(root:GetStringHeight() or 0, L.rootSize)
        local treeHeight = rootHeight + L.rootGap + #self._items * L.rowHeight
        for i = 1, #self._items do
            local row = self._rows:Get(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", stack, "TOPLEFT", 0, -(rootHeight + L.rootGap + (i - 1) * L.rowHeight))
            row:SetWidth(widest)
        end
        stack:SetWidth(math.max(widest, 1))
        stack:SetHeight(treeHeight + L.treeGap + (self._find:GetHeight() or 0))
    end

    -- The selection Blizzard's panel holds, found among the rows
    function panel:PaintSelection()
        local cs = CategoryPanel()
        local selectedCategory = cs and GF.plainNumber(cs.selectedCategory)
        local selectedFilters = cs and GF.plainNumber(cs.selectedFilters)
        for i, item in ipairs(self._items) do
            local on = selectedCategory ~= nil and item.categoryID == selectedCategory
                and item.filters == selectedFilters
            self._rows:Get(i)._backdrop:SetSelected(on)
        end
    end

    function panel:RefreshItems()
        local items = Items()
        self._items = items
        for i, item in ipairs(items) do
            local row = self._rows:Get(i)
            row._item = item
            addon.UI.Theme:ApplyFont(row._label, "label", L.labelSize)
            row._label:SetText(item.label or "")
            PlaceTrunk(row, i == 1, i == #items)
            PaintLines(row)
            row:Show()
        end
        self._rows:HideFrom(#items + 1)
        self:PaintSelection()
        self:Layout()
        C_Timer.After(0, function()
            if self:IsShown() then self:Layout() end
        end)
    end

    -- Find Group follows Blizzard's nav rules: a category, and an account
    -- that may speak. A missing category is plain to see; a silenced account
    -- is the tooltip's. Start Group adds the leader and queue rules.
    function panel:RefreshButtons()
        local cs = CategoryPanel()
        local selected = cs and GF.plainNumber(cs.selectedCategory)
        local findOn, reason = selected ~= nil, nil
        if C_SocialRestrictions then
            if C_SocialRestrictions.IsSilenced and C_SocialRestrictions.IsSilenced() then
                findOn = false
                reason = Str("ERR_ACCOUNT_SILENCED", "This account is silenced")
            elseif C_SocialRestrictions.IsSquelched and C_SocialRestrictions.IsSquelched() then
                findOn = false
                reason = Str("ERR_USER_SQUELCHED", "This account is squelched")
            end
        end
        self._findReason = reason
        self._find:SetEnabled(findOn)
        local startReason = GF.StartGroupBlock()
        self._startReason = startReason
        self._start:SetEnabled(selected ~= nil and startReason == nil)
    end

    function panel:Refresh()
        self:RefreshItems()
        self:RefreshButtons()
    end

    function panel:Cleanup()
        self._rows:HideFrom(1)
    end

    GF.Listen("categories", function()
        if panel:IsShown() then panel:Refresh() end
    end)
    GF.Listen("buttons", function()
        if panel:IsShown() then panel:RefreshButtons() end
    end)

    -- The tree's lines follow the accent; the root is one of the window's
    -- accent strings
    addon.UI.Theme:Subscribe("GroupFinderCategoryTree", function()
        for i = 1, panel._rows:Count() do
            PaintLines(panel._rows:Get(i))
        end
    end)

    return panel
end

UI.panelBuilders.categories = Build
