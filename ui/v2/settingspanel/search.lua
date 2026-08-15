-- search.lua - Settings Search: index building, search algorithm, renderer, navigate-to-result
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls
local Navigation = addon.UI.Navigation
local Builder = addon.UI.SettingsBuilder

local CONTENT_PADDING = 8
local ROW_HEIGHT = 24
local RESULT_START_Y = -48  -- Below search input
local INPUT_HEIGHT = 32
local DEBOUNCE_DELAY = 0.15

--------------------------------------------------------------------------------
-- Search State
--------------------------------------------------------------------------------

local Search = {}
UIPanel._search = Search

Search._index = nil
Search._query = ""
Search._results = nil
Search._resultRows = {}
Search._statusText = nil
Search._searchInput = nil
Search._debounceTimer = nil

-- Maps built during index construction
Search._breadcrumbMap = nil
Search._moduleCategoryMap = nil

--------------------------------------------------------------------------------
-- Class Aura Filtering
--------------------------------------------------------------------------------

local CLASS_AURA_TOKENS = {
    classAurasDeathKnight = "DEATHKNIGHT",
    classAurasDemonHunter = "DEMONHUNTER",
    classAurasDruid = "DRUID",
    classAurasEvoker = "EVOKER",
    classAurasHunter = "HUNTER",
    classAurasMage = "MAGE",
    classAurasMonk = "MONK",
    classAurasPaladin = "PALADIN",
    classAurasPriest = "PRIEST",
    classAurasRogue = "ROGUE",
    classAurasShaman = "SHAMAN",
    classAurasWarlock = "WARLOCK",
    classAurasWarrior = "WARRIOR",
}

local function ShouldSkipRenderer(key)
    local classToken = CLASS_AURA_TOKENS[key]
    if classToken then
        local _, playerClass = UnitClass("player")
        return classToken ~= playerClass
    end
    if key == "debugMenu" then
        local debugEnabled = addon.db and addon.db.profile and addon.db.profile.debugMenuEnabled
        return not debugEnabled
    end
    return false
end

--------------------------------------------------------------------------------
-- Non-builder renderer keys (skip during scan, use manual entries instead)
--------------------------------------------------------------------------------

local SKIP_SCAN = {
    startHere = true,
    profilesManage = true,
    profilesPresets = true,
    profilesRules = true,
    profilesImportExport = true,
    applyAllFonts = true,
    applyAllTextures = true,
    scootAurasList = true,
    search = true,
}

local MANUAL_ENTRIES = {
    {
        type = "toggle",
        label = "Enable Spec Profiles",
        description = "Automatically switch profiles when you change specializations.",
        rendererKey = "profilesManage",
    },
    {
        type = "font",
        label = "Font",
        description = "Select a font to apply across all Scoot settings.",
        rendererKey = "applyAllFonts",
    },
    {
        type = "texture",
        label = "Texture",
        description = "Select a bar texture to apply across all Scoot settings.",
        rendererKey = "applyAllTextures",
    },
    -- ScootAuras: the Aura List page is hand-rolled, so the scanner never
    -- sees it; these entries make its flows findable.
    {
        type = "page",
        label = "Aura List",
        description = "ScootAuras: track any buff or debuff as an icon, bar, or shape on player, target, or focus.",
        rendererKey = "scootAurasList",
    },
    {
        type = "button",
        label = "Add Aura",
        description = "Create a custom aura tracker from a spell ID or the cooldown catalog.",
        rendererKey = "scootAurasList",
    },
    {
        type = "button",
        label = "Add Group",
        description = "Group aura trackers to arrange and move them together.",
        rendererKey = "scootAurasList",
    },
}

--------------------------------------------------------------------------------
-- Breadcrumb Computation
--------------------------------------------------------------------------------

-- Child -> parent lookups live in deeplink.lua now; navigation goes through
-- addon.UI:OpenToPage.
local function BuildBreadcrumbMap()
    local breadcrumbs = {}
    local moduleCategories = {}

    for _, parent in ipairs(Navigation.NavModel) do
        if parent.children then
            for _, child in ipairs(parent.children) do
                breadcrumbs[child.key] = parent.label .. " > " .. child.label
                if child.module then
                    moduleCategories[child.key] = child.module
                end
            end
        elseif parent.key ~= "search" then
            breadcrumbs[parent.key] = parent.label
        end
    end

    Search._breadcrumbMap = breadcrumbs
    Search._moduleCategoryMap = moduleCategories
end

--------------------------------------------------------------------------------
-- Index Building
--------------------------------------------------------------------------------

function Search:BuildIndex()
    if not UIPanel._renderers then return end
    if not Search._breadcrumbMap then BuildBreadcrumbMap() end

    Builder._scanMode = true
    Builder._scanEntries = {}

    local panel = UIPanel
    local frame = panel.frame
    if not frame or not frame._contentPane then
        Builder._scanMode = false
        return
    end
    local scrollContent = frame._contentPane._scrollContent
    if not scrollContent then
        Builder._scanMode = false
        return
    end

    -- Temporarily suppress search cleanup so renderers calling ClearContent
    -- don't destroy the search UI during scan
    local savedSearchCleanup = panel._searchCleanup
    panel._searchCleanup = nil

    for key, renderer in pairs(UIPanel._renderers) do
        -- Skip non-builder renderers, filtered renderers, individual action bar renderers
        if not SKIP_SCAN[key]
            and not ShouldSkipRenderer(key)
            and not key:match("^actionBar%d$")
        then
            Builder._scanRendererKey = key
            Builder._scanSectionStack = {}

            local ok, err = pcall(renderer, panel, scrollContent)
            -- Silently skip renderers that error during scan

            -- Clean up any partial builder state
            if panel._currentBuilder then
                panel._currentBuilder:Cleanup()
                panel._currentBuilder = nil
            end
        end
    end

    -- Restore search cleanup
    panel._searchCleanup = savedSearchCleanup

    -- Add manual entries for non-builder pages
    for _, entry in ipairs(MANUAL_ENTRIES) do
        table.insert(Builder._scanEntries, {
            type = entry.type,
            label = entry.label,
            description = entry.description,
            rendererKey = entry.rendererKey,
            section = nil,
        })
    end

    -- Augment entries with breadcrumbs and module categories
    local index = {}
    for _, entry in ipairs(Builder._scanEntries) do
        local breadcrumb = Search._breadcrumbMap[entry.rendererKey] or entry.rendererKey
        local sectionInfo = entry.section

        -- Append section/tab title to breadcrumb
        if sectionInfo then
            local sectionTitle = type(sectionInfo) == "table" and sectionInfo.title or sectionInfo
            if sectionTitle then
                breadcrumb = breadcrumb .. " > " .. sectionTitle
            end
        end

        table.insert(index, {
            type = entry.type,
            label = entry.label,
            description = entry.description,
            rendererKey = entry.rendererKey,
            breadcrumb = breadcrumb,
            section = sectionInfo,
            moduleCategory = Search._moduleCategoryMap[entry.rendererKey],
        })
    end

    -- Clean up scan state
    Builder._scanMode = false
    Builder._scanEntries = {}
    Builder._scanRendererKey = nil
    Builder._scanSectionStack = {}

    Search._index = index
end

--------------------------------------------------------------------------------
-- Search Algorithm
--------------------------------------------------------------------------------

function Search:Execute(query)
    if not Search._index then
        Search:BuildIndex()
    end
    if not Search._index then return {} end

    local queryLower = query:lower()
    if queryLower == "" then return {} end

    local tier1, tier2, tier3 = {}, {}, {}

    for _, entry in ipairs(Search._index) do
        local labelLower = entry.label:lower()
        local descLower = entry.description:lower()

        if labelLower:find(queryLower, 1, true) == 1 then
            table.insert(tier1, entry)
        elseif labelLower:find(queryLower, 1, true) then
            table.insert(tier2, entry)
        elseif descLower:find(queryLower, 1, true) then
            table.insert(tier3, entry)
        end
    end

    local function sortByBreadcrumb(a, b)
        return a.breadcrumb < b.breadcrumb
    end
    table.sort(tier1, sortByBreadcrumb)
    table.sort(tier2, sortByBreadcrumb)
    table.sort(tier3, sortByBreadcrumb)

    local results = {}
    for _, e in ipairs(tier1) do table.insert(results, e) end
    for _, e in ipairs(tier2) do table.insert(results, e) end
    for _, e in ipairs(tier3) do table.insert(results, e) end

    return results
end

--------------------------------------------------------------------------------
-- Navigate to Result
--------------------------------------------------------------------------------

local function IsModuleDisabled(entry)
    if not entry.moduleCategory then return false end
    if not addon._activeModules then return false end
    return addon._activeModules[entry.moduleCategory] == false
end

function Search:HighlightControl(control)
    if not control then return end

    local highlight = CreateFrame("Frame", nil, control)
    highlight:SetAllPoints(control)
    highlight:SetFrameLevel(control:GetFrameLevel() + 5)

    local tex = highlight:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    local ar, ag, ab = Theme:GetAccentColor()
    tex:SetColorTexture(ar, ag, ab, 0.3)

    local elapsed = 0
    highlight:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.5 then return end

        local fadeProgress = (elapsed - 0.5) / 1.0
        if fadeProgress >= 1 then
            self:Hide()
            self:SetParent(nil)
            return
        end

        tex:SetColorTexture(ar, ag, ab, 0.3 * (1 - fadeProgress))
    end)
end

function Search:FindAndScrollToControl(entry)
    local builder = UIPanel._currentBuilder
    if not builder or not builder._controls then return end

    local targetLabel = entry.label
    local targetSection = nil
    if entry.section then
        targetSection = type(entry.section) == "table" and entry.section.title or entry.section
    end

    for _, control in ipairs(builder._controls) do
        local isMatch = control._searchLabel == targetLabel
        if isMatch and targetSection then
            isMatch = control._searchSection == targetSection
        end

        if isMatch then
            -- Scroll to this control
            local frame = UIPanel.frame
            if not frame or not frame._contentPane then return end
            local scrollFrame = frame._contentPane._scrollFrame
            local scrollContent = frame._contentPane._scrollContent
            if not scrollFrame or not scrollContent then return end

            local controlTop = control:GetTop()
            local scrollContentTop = scrollContent:GetTop()

            if controlTop and scrollContentTop then
                local offset = scrollContentTop - controlTop - 20
                offset = math.max(0, offset)
                scrollFrame:SetVerticalScroll(offset)

                if frame._contentPane._scrollbar and frame._contentPane._scrollbar.Update then
                    frame._contentPane._scrollbar:Update()
                end
            end

            Search:HighlightControl(control)
            return
        end
    end
end

function Search:NavigateToResult(entry)
    if IsModuleDisabled(entry) then
        -- Send the user to Features so they can enable the module.
        addon.UI:OpenToPage("startHere")
        return
    end

    local sectionInfo = (type(entry.section) == "table") and entry.section or nil

    local ok = addon.UI:OpenToPage(entry.rendererKey, sectionInfo and {
        componentId = sectionInfo.componentId,
        sectionKey  = sectionInfo.sectionKey,
        tab         = sectionInfo.tab,
    } or nil)
    if not ok then return end

    -- Search-only: scroll the matched control into view and flash it.
    local delay = sectionInfo and 0.15 or 0.05
    C_Timer.After(delay, function()
        Search:FindAndScrollToControl(entry)
    end)
end

--------------------------------------------------------------------------------
-- Results Rendering
--------------------------------------------------------------------------------

local function ClearResultRows()
    for _, row in ipairs(Search._resultRows) do
        if row.Hide then row:Hide() end
        if row.SetParent then row:SetParent(nil) end
    end
    Search._resultRows = {}
end

local function ClearStatusText()
    if Search._statusText then
        Search._statusText:Hide()
        Search._statusText:SetParent(nil)
        Search._statusText = nil
    end
end

function Search:RenderResults(scrollContent)
    ClearResultRows()
    ClearStatusText()

    local ar, ag, ab = Theme:GetAccentColor()
    local fontPath = Theme:GetFont("VALUE")
    local headerFontPath = Theme:GetFont("HEADER")
    local query = Search._query or ""
    local results = Search._results or {}
    local yOffset = RESULT_START_Y

    -- Status line (result count / empty / no results)
    local statusFS = scrollContent:CreateFontString(nil, "OVERLAY")
    statusFS:SetFont(fontPath, 11, "")
    statusFS:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, yOffset)
    statusFS:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, yOffset)
    statusFS:SetJustifyH("LEFT")
    Search._statusText = statusFS

    if query == "" then
        statusFS:SetText("Type to search across all settings...")
        statusFS:SetTextColor(0.5, 0.5, 0.5, 0.6)
        scrollContent:SetHeight(math.abs(yOffset) + 40)
        return
    end

    if #results == 0 then
        statusFS:SetText("No settings found for \"" .. query .. "\"")
        statusFS:SetTextColor(0.5, 0.5, 0.5, 0.6)
        scrollContent:SetHeight(math.abs(yOffset) + 40)
        return
    end

    statusFS:SetText(#results .. " result" .. (#results ~= 1 and "s" or "") .. " for \"" .. query .. "\"")
    statusFS:SetTextColor(0.5, 0.5, 0.5, 0.8)
    yOffset = yOffset - 20

    -- Result rows
    for i, entry in ipairs(results) do
        local isDisabled = IsModuleDisabled(entry)
        local alphaMultiplier = isDisabled and 0.4 or 1.0

        local row = CreateFrame("Button", nil, scrollContent)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
        row:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, yOffset)
        row:EnableMouse(true)
        row:RegisterForClicks("AnyUp")

        -- Hover background
        local hoverBg = row:CreateTexture(nil, "BACKGROUND")
        hoverBg:SetAllPoints()
        hoverBg:SetColorTexture(ar, ag, ab, 0.08)
        hoverBg:Hide()
        row._hoverBg = hoverBg

        -- Breadcrumb text (left side)
        local breadcrumbFS = row:CreateFontString(nil, "OVERLAY")
        breadcrumbFS:SetFont(fontPath, 11, "")
        breadcrumbFS:SetPoint("LEFT", row, "LEFT", CONTENT_PADDING, 0)
        breadcrumbFS:SetTextColor(ar * 0.7, ag * 0.7, ab * 0.7, 0.7 * alphaMultiplier)
        breadcrumbFS:SetText(entry.breadcrumb)
        breadcrumbFS:SetJustifyH("LEFT")

        -- Type badge (right side)
        local badgeFS = row:CreateFontString(nil, "OVERLAY")
        badgeFS:SetFont(fontPath, 10, "")
        badgeFS:SetPoint("RIGHT", row, "RIGHT", -CONTENT_PADDING, 0)
        badgeFS:SetTextColor(0.5, 0.5, 0.5, 0.5 * alphaMultiplier)
        badgeFS:SetText("[" .. entry.type .. "]")
        badgeFS:SetJustifyH("RIGHT")

        -- Setting label (before badge)
        local labelFS = row:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont(fontPath, 12, "")
        labelFS:SetPoint("RIGHT", badgeFS, "LEFT", -8, 0)
        labelFS:SetTextColor(1, 1, 1, alphaMultiplier)
        labelFS:SetText(entry.label)
        labelFS:SetJustifyH("RIGHT")

        -- Fill line between breadcrumb and label
        local fillLine = row:CreateTexture(nil, "ARTWORK")
        fillLine:SetHeight(1)
        fillLine:SetPoint("LEFT", breadcrumbFS, "RIGHT", 8, 0)
        fillLine:SetPoint("RIGHT", labelFS, "LEFT", -8, 0)
        fillLine:SetColorTexture(ar, ag, ab, 0.15 * alphaMultiplier)

        -- Hover / click behavior
        if not isDisabled then
            row:SetScript("OnEnter", function(self)
                self._hoverBg:Show()
            end)
            row:SetScript("OnLeave", function(self)
                self._hoverBg:Hide()
            end)
        else
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Enable this module on the 'Features' page.", 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
            end)
        end

        row:SetScript("OnClick", function()
            Search:NavigateToResult(entry)
        end)

        table.insert(Search._resultRows, row)
        yOffset = yOffset - ROW_HEIGHT
    end

    scrollContent:SetHeight(math.abs(yOffset) + CONTENT_PADDING)

    -- Update scrollbar
    local frame = UIPanel.frame
    if frame and frame._contentPane and frame._contentPane._scrollbar and frame._contentPane._scrollbar.Update then
        C_Timer.After(0.02, function()
            frame._contentPane._scrollbar:Update()
        end)
    end
end

--------------------------------------------------------------------------------
-- Search Renderer
--------------------------------------------------------------------------------

local function CleanupSearchControls()
    -- Cancel debounce timer
    if Search._debounceTimer then
        Search._debounceTimer:Cancel()
        Search._debounceTimer = nil
    end

    -- Clear result rows
    ClearResultRows()
    ClearStatusText()

    -- Clear search input and prompt
    if Search._searchInput then
        if Search._searchInput.Cleanup then Search._searchInput:Cleanup() end
        if Search._searchInput.Hide then Search._searchInput:Hide() end
        if Search._searchInput.SetParent then Search._searchInput:SetParent(nil) end
        Search._searchInput = nil
    end
end

function Search:RenderSearchPage(panel, scrollContent)
    -- Store cleanup function on panel for ClearContent
    panel._searchCleanup = CleanupSearchControls

    local ar, ag, ab = Theme:GetAccentColor()
    local fontPath = Theme:GetFont("VALUE")

    -- Search input
    local searchInput = Controls:CreateSingleLineEditBox({
        parent = scrollContent,
        placeholder = "Search all settings...",
        text = Search._query or "",
        fontSize = 13,
    })

    if searchInput then
        searchInput:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, -CONTENT_PADDING)
        searchInput:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, -CONTENT_PADDING)
        Search._searchInput = searchInput

        -- Auto-focus with cursor at end
        C_Timer.After(0, function()
            if searchInput._editBox then
                searchInput._editBox:SetFocus()
                searchInput._editBox:SetCursorPosition(searchInput._editBox:GetNumLetters())
            end
        end)

        -- Real-time filtering with debounce
        if searchInput._editBox then
            searchInput._editBox:HookScript("OnTextChanged", function(self, userInput)
                if not userInput then return end
                local query = self:GetText()
                Search._query = query

                if Search._debounceTimer then
                    Search._debounceTimer:Cancel()
                end
                Search._debounceTimer = C_Timer.NewTimer(DEBOUNCE_DELAY, function()
                    Search._results = Search:Execute(query)
                    Search:RenderResults(scrollContent)
                end)
            end)

            -- Escape clears input
            searchInput._editBox:SetScript("OnEscapePressed", function(self)
                self:SetText("")
                Search._query = ""
                Search._results = nil
                Search:RenderResults(scrollContent)
                self:SetFocus()
            end)
        end
    end

    -- Render existing results (state preservation) or initial empty state
    if Search._query and Search._query ~= "" and Search._results then
        Search:RenderResults(scrollContent)
    elseif Search._query and Search._query ~= "" then
        Search._results = Search:Execute(Search._query)
        Search:RenderResults(scrollContent)
    else
        Search:RenderResults(scrollContent)
    end
end

--------------------------------------------------------------------------------
-- Renderer Registration
--------------------------------------------------------------------------------

UIPanel:RegisterRenderer("search", function(panel, scrollContent)
    Search:RenderSearchPage(panel, scrollContent)
end)

--------------------------------------------------------------------------------
-- Profile Invalidation
--------------------------------------------------------------------------------

C_Timer.After(0, function()
    if addon.db and addon.db.RegisterCallback then
        local callbackObj = {}
        function callbackObj:InvalidateSearch()
            Search._index = nil
        end
        addon.db.RegisterCallback(callbackObj, "OnProfileChanged", "InvalidateSearch")
        addon.db.RegisterCallback(callbackObj, "OnProfileCopied", "InvalidateSearch")
        addon.db.RegisterCallback(callbackObj, "OnProfileReset", "InvalidateSearch")
        addon.db.RegisterCallback(callbackObj, "OnNewProfile", "InvalidateSearch")
    end
end)
