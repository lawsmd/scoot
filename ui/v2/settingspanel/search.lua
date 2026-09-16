-- search.lua - Settings Search: index building, search algorithm, renderer, navigate-to-result
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls
local Navigation = addon.UI.Navigation
local Builder = addon.UI.SettingsBuilder
local Matcher = addon.UI.SearchMatch

local CONTENT_PADDING = 8
local ROW_HEIGHT = 24
local RESULT_START_Y = -48  -- Below search input
local INPUT_HEIGHT = 32
local DEBOUNCE_DELAY = 0.15

--------------------------------------------------------------------------------
-- Limits
--------------------------------------------------------------------------------
-- Search policy, kept in a table rather than in file constants: a skin has no
-- business deciding when a query is too short or a result list too long, and
-- the debug command can print the table as it stands.
--
-- minQuery 2 and not 3: "UI", "HP" and "XP" are real queries.
-- maxRows 60: pooling removes the allocation cost of a long list, not the
-- layout cost. Sixty rows is about two screens at the default panel height,
-- long enough to read as complete and short enough that a keystroke stays
-- inside one frame.
local Limits = {
    minQuery = 2,
    maxRows  = 60,
}

--------------------------------------------------------------------------------
-- Search State
--------------------------------------------------------------------------------

local Search = {}
UIPanel._search = Search

Search.Limits = Limits

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

local function ShouldSkipRenderer(key)
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
        label = "Header Font",
        description = "Set the Global Header Font that font fields holding its token follow.",
        rendererKey = "applyAllFonts",
    },
    {
        type = "font",
        label = "Body Font",
        description = "Set the Global Body Font that font fields holding its token follow.",
        rendererKey = "applyAllFonts",
    },
    {
        type = "texture",
        label = "Bar Texture",
        description = "Set the Global Bar Texture that texture fields holding its token follow.",
        rendererKey = "applyAllTextures",
    },
    -- ScootAuras: the Aura List page is hand-rolled, so the scanner never
    -- sees it; these entries make its flows findable. The page itself needs no
    -- row here, because page entries come from the nav model.
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
    {
        type = "search",
        label = "Search Auras",
        description = "Filter the Aura List by tracker name, aura name, or spell ID.",
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
    local pageKeywords = {}

    for _, parent in ipairs(Navigation.NavModel) do
        if parent.children then
            for _, child in ipairs(parent.children) do
                breadcrumbs[child.key] = parent.label .. " > " .. child.label
                if child.module then
                    moduleCategories[child.key] = child.module
                end
                -- versionBadge.title is the page's other name ("Player Frame X"),
                -- and it is the only spare prose the nav model carries. Every
                -- setting on the page inherits it as keywords.
                if child.versionBadge and child.versionBadge.title then
                    pageKeywords[child.key] = child.versionBadge.title
                end
            end
        elseif parent.key ~= "search" then
            breadcrumbs[parent.key] = parent.label
        end
    end

    Search._breadcrumbMap = breadcrumbs
    Search._moduleCategoryMap = moduleCategories
    Search._pageKeywordMap = pageKeywords
end

--------------------------------------------------------------------------------
-- Index Building
--------------------------------------------------------------------------------

-- Declared above BuildIndex because BuildIndex reads it to set entry.demoted.
-- Below it, the upvalue is nil at build time and every entry scores undemoted.
local function IsModuleDisabled(entry)
    if not entry.moduleCategory then return false end
    if not addon._activeModules then return false end
    return addon._activeModules[entry.moduleCategory] == false
end

--- Flatten strings and arrays of strings into one space-joined string, or nil.
local function JoinTerms(...)
    local parts = nil
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "string" and value ~= "" then
            parts = parts or {}
            parts[#parts + 1] = value
        elseif type(value) == "table" then
            for j = 1, #value do
                if type(value[j]) == "string" and value[j] ~= "" then
                    parts = parts or {}
                    parts[#parts + 1] = value[j]
                end
            end
        end
    end
    return parts and table.concat(parts, " ") or nil
end

-- The matcher reads entry.fields and nothing else. Normalize memoizes on the
-- raw string, so the hundreds of rows labelled "Size" and the one page path
-- every row on a page shares each fold once.
local function AttachFields(entry)
    entry.fields = {
        label       = Matcher.Normalize(entry.label),
        keywords    = Matcher.Normalize(entry.keywords),
        path        = Matcher.Normalize(entry.pagePath),
        section     = Matcher.Normalize(entry.sectionTitle),
        description = Matcher.Normalize(entry.description),
        type        = Matcher.Normalize(entry.type),
    }
end

-- Page entries come from the nav model, not from the scan, so a page whose
-- renderer the scan skips still has one. That is what makes the profile pages,
-- both Apply All pages and the hand-rolled Aura List findable: a scan can never
-- reach them. Nav visibility is asked of Navigation rather than restated, so
-- search never offers a page the sidebar is hiding.
local function BuildPageEntries(out)
    local vocab = addon.SearchVocabulary
    local pages = (vocab and vocab.pages) or {}

    for _, parent in ipairs(Navigation.NavModel) do
        if Navigation:IsParentVisible(parent) then
            for _, child in ipairs(Navigation:GetVisibleChildren(parent)) do
                local badge = child.versionBadge
                local record = {
                    kind = "page",
                    type = "page",
                    label = child.label,
                    description = (badge and badge.text) or "",
                    rendererKey = child.key,
                    breadcrumb = parent.label .. " > " .. child.label,
                    pagePath = parent.label .. " " .. child.label,
                    sectionTitle = nil,
                    keywords = JoinTerms(pages[child.key], pages[parent.key], badge and badge.title),
                    moduleCategory = child.module,
                }
                record.demoted = IsModuleDisabled(record)
                AttachFields(record)
                out[#out + 1] = record
            end
        end
    end
end

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
    local ordinals = {}
    for _, entry in ipairs(Builder._scanEntries) do
        local pagePath = Search._breadcrumbMap[entry.rendererKey] or entry.rendererKey
        local breadcrumb = pagePath
        local sectionInfo = entry.section
        local sectionTitle = nil

        -- Append section/tab title to breadcrumb
        if sectionInfo then
            sectionTitle = type(sectionInfo) == "table" and sectionInfo.title or sectionInfo
            if sectionTitle then
                breadcrumb = breadcrumb .. " > " .. sectionTitle
            end
        end

        -- The scan walks a page in render order, so a counter per page and
        -- label is the cheapest way to tell two rows sharing a label apart.
        local ordinalKey = entry.rendererKey .. "\0" .. entry.label
        ordinals[ordinalKey] = (ordinals[ordinalKey] or 0) + 1

        local moduleCategory = Search._moduleCategoryMap[entry.rendererKey]
        local record = {
            kind = "setting",
            type = entry.type,
            label = entry.label,
            description = entry.description,
            rendererKey = entry.rendererKey,
            breadcrumb = breadcrumb,
            pagePath = pagePath,
            sectionTitle = sectionTitle,
            keywords = Search._pageKeywordMap and Search._pageKeywordMap[entry.rendererKey] or nil,
            ordinal = ordinals[ordinalKey],
            section = sectionInfo,
            moduleCategory = moduleCategory,
        }
        record.demoted = IsModuleDisabled(record)
        AttachFields(record)
        table.insert(index, record)
    end

    BuildPageEntries(index)

    -- Features is a header button rather than a nav entry, so no page entry is
    -- generated for it, and it is where every disabled-module result already
    -- sends people.
    local features = {
        kind = "page",
        type = "page",
        label = "Features",
        description = "Turn each part of the addon on or off.",
        rendererKey = "startHere",
        breadcrumb = "Features",
        pagePath = "Features",
        keywords = "modules enable disable",
    }
    AttachFields(features)
    table.insert(index, features)

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

--- Rank the index against a query. Returns the scored records and the parsed
--- query; a record is { entry, score, fields, contextOnly, rank }.
function Search:Execute(query)
    if not Search._index then
        Search:BuildIndex()
    end
    if not Search._index then return {} end

    local results, parsed = Matcher.Run(Search._index, query)
    Search._parsed = parsed
    return results
end

--------------------------------------------------------------------------------
-- Navigate to Result
--------------------------------------------------------------------------------

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

    -- A page entry names no control, so there is nothing to scroll to and the
    -- walk would only find a setting that happens to share the page's name.
    if entry.kind == "page" then return end

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

    local trimmed = query:match("^%s*(.-)%s*$") or ""

    if trimmed == "" then
        statusFS:SetText("Type to search across all settings...")
        statusFS:SetTextColor(0.5, 0.5, 0.5, 0.6)
        scrollContent:SetHeight(math.abs(yOffset) + 40)
        return
    end

    if #trimmed < Limits.minQuery then
        statusFS:SetText("Keep typing to search.")
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

    local shown = math.min(#results, Limits.maxRows)
    if shown < #results then
        statusFS:SetText("Showing " .. shown .. " of " .. #results
            .. " results for \"" .. query .. "\". Type more to narrow.")
    else
        statusFS:SetText(#results .. " result" .. (#results ~= 1 and "s" or "") .. " for \"" .. query .. "\"")
    end
    statusFS:SetTextColor(0.5, 0.5, 0.5, 0.8)
    yOffset = yOffset - 20

    -- Result rows
    for i = 1, shown do
        local entry = results[i].entry
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
-- Debug Command
--------------------------------------------------------------------------------
-- The instrument for every ranking claim: it prints the score and the fields
-- that carried it, so a "why did that rank there" question has an answer that
-- does not need the panel open.

addon:RegisterDebugCommand({
    name = "search",
    help = "Rank a settings query and show the scores; 'search limits' prints the policy numbers",
    handler = function(sub, rest)
        local lines, push = addon.DebugLines()

        if sub == "limits" then
            push("Limits:")
            for key, value in pairs(Limits) do
                push("  %-10s %s", key, tostring(value))
            end
            addon.DebugShowWindow("Settings Search", lines)
            return
        end

        local query = sub or ""
        if rest and #rest > 0 then
            query = query .. " " .. table.concat(rest, " ")
        end

        local results = Search:Execute(query)
        local parsed = Search._parsed
        push("query   %s", query ~= "" and query or "(empty)")
        push("index   %d entries", #(Search._index or {}))
        push("terms   %s", parsed and parsed.head or "(too short to rank)")
        push("matched %d", #results)
        push("")
        for i = 1, math.min(#results, 30) do
            local r = results[i]
            local fields = {}
            for key in pairs(r.fields or {}) do fields[#fields + 1] = key end
            table.sort(fields)
            push("%6.2f  %-7s %-34s %-44s [%s]",
                r.score,
                r.entry.kind or "setting",
                r.entry.label or "",
                r.entry.breadcrumb or "",
                table.concat(fields, ","))
        end

        addon.DebugShowWindow("Settings Search", lines)
    end,
})

--------------------------------------------------------------------------------
-- Profile Invalidation
--------------------------------------------------------------------------------

--- Drop the index and everything derived from it. Clearing _results as well
--- matters: RenderSearchPage only re-executes when _results is nil, so a
--- profile switch used to repaint records built against the old index.
function Search:Invalidate()
    Search._index = nil
    Search._breadcrumbMap = nil
    Search._moduleCategoryMap = nil
    Search._pageKeywordMap = nil
    Search._results = nil
    Search._parsed = nil
    if Matcher then
        Matcher.ResetCache()
        Matcher.InvalidateVocabulary()
    end
end

C_Timer.After(0, function()
    if addon.db and addon.db.RegisterCallback then
        local callbackObj = {}
        function callbackObj:InvalidateSearch()
            Search:Invalidate()
        end
        addon.db.RegisterCallback(callbackObj, "OnProfileChanged", "InvalidateSearch")
        addon.db.RegisterCallback(callbackObj, "OnProfileCopied", "InvalidateSearch")
        addon.db.RegisterCallback(callbackObj, "OnProfileReset", "InvalidateSearch")
        addon.db.RegisterCallback(callbackObj, "OnNewProfile", "InvalidateSearch")
    end
end)
