-- settingspanel/core.lua - Panel construction, initialization, public API, combat safety
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel
local Theme = addon.UI.Theme
local Window = addon.UI.Window
local Controls = addon.UI.Controls
local Chrome = addon.UI.Chrome
local Navigation = addon.UI.Navigation
local SettingsBuilder = addon.UI.SettingsBuilder

-- Frame names carry the brand because both addons load this file in the
-- retail client and one global cannot hold two frames. Scoot leaves
-- addon.Brand unset and keeps the names it has always had.
local BRAND = addon.Brand or "Scoot"

-- The product's title and toolbar, read at call time; Scoot's is
-- ui/v2/settings/HeaderModel.lua and Camelot's is forever/menu.lua.
local function HeaderModel()
    return UIPanel.HeaderModel or {}
end

-- Every layout number here comes from the active skin's metrics: the panel
-- size and bounds, titleBarHeight, closeButton, resizeGrip, toolbar, pulse,
-- contentHeaderHeight (a page may grow the header, see _headerBaseHeight),
-- navWidth, scrollBar, paneInset and home.
local function M()
    return Controls.Metrics()
end

-- Panel State

UIPanel.frame = nil
UIPanel._initialized = false
UIPanel._currentCategoryKey = nil    -- Currently displayed category
UIPanel._pendingBackSync = {}        -- Components needing refresh from Edit Mode back-sync
UIPanel._currentBuilder = nil

-- Initialization

function UIPanel:Initialize()
    if self._initialized then return end

    local savedWidth, savedHeight = M().panelWidth, M().panelHeight
    if addon.db and addon.db.global and addon.db.global.windowSize then
        local size = addon.db.global.windowSize
        savedWidth = size.width or M().panelWidth
        savedHeight = size.height or M().panelHeight
    end

    local frame = Window:Create(BRAND .. "SettingsFrame", UIParent, savedWidth, savedHeight)
    frame:SetPoint("CENTER")
    frame:Hide()
    self.frame = frame

    frame:SetResizable(true)
    frame:SetResizeBounds(M().panelMinWidth, M().panelMinHeight, M().panelMaxWidth, M().panelMaxHeight)

    self:CreateTitleBar()
    self:CreateCloseButton()
    self:CreateHeaderButtons()
    self:CreateResizeHandle()
    self:CreateNavigation()
    self:CreateContentPane()

    tinsert(UISpecialFrames, BRAND .. "SettingsFrame")

    frame:SetScript("OnHide", function()
        if addon.CloseFontPicker then addon.CloseFontPicker() end
        if addon.CloseBarTexturePicker then addon.CloseBarTexturePicker() end
        if addon.CloseBarBorderPicker then addon.CloseBarBorderPicker() end
        if addon.CloseIconPicker then addon.CloseIconPicker() end
        if addon.CloseScootAuraEditor then addon.CloseScootAuraEditor() end
        -- The Aura List's fly-outs float over the window on their own frames.
        if addon.ScootAurasUI and addon.ScootAurasUI.CloseFlyouts then
            addon.ScootAurasUI.CloseFlyouts()
        end
    end)

    Window:RestorePosition(frame)

    self._initialized = true
end

-- Title Bar: the drag region across the top, and the product's title drawn
-- the way the skin's titleBar role says

local function SaveWindowPosition(frame)
    if addon.db and addon.db.global then
        local point, _, relPoint, x, y = frame:GetPoint()
        addon.db.global.windowPosition = {
            point = point,
            relPoint = relPoint,
            x = x,
            y = y
        }
    end
end

function UIPanel:CreateTitleBar()
    local frame = self.frame
    if not frame then return end

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(M().titleBarHeight)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SaveWindowPosition(frame)
    end)

    frame._titleBar = titleBar
    frame._title = self:CreateTitle(titleBar)
end

-- The title handle: SetHome(isHome) while the home page is up, Reveal(animate)
-- when a page comes up, Cleanup(). ascii is the block-letter logo with its
-- column reveal and a click home; text is the product name in the header
-- role or the role's fontObject; texture is the product's own image. A role
-- the model has no art for falls back to text.
function UIPanel:CreateTitle(titleBar)
    local frame = self.frame
    local model = HeaderModel().title or {}
    local spec = Chrome.Spec("titleBar")
    local kind = spec.kind
    if kind == "ascii" and not model.ascii then kind = "text" end
    if kind == "texture" and not model.texture then kind = "text" end
    local panel = self
    local handle = { kind = kind }

    local function passDrag(btn)
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", function() frame:StartMoving() end)
        btn:SetScript("OnDragStop", function()
            frame:StopMovingOrSizing()
            SaveWindowPosition(frame)
        end)
    end

    if kind == "ascii" then
        local logoBtn = CreateFrame("Button", BRAND .. "LogoBtn", titleBar)
        logoBtn:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 10, -6)
        logoBtn:EnableMouse(true)
        logoBtn:RegisterForClicks("AnyUp")

        local ar, ag, ab = Theme:GetAccentColor()
        local logo = logoBtn:CreateFontString(nil, "OVERLAY")
        Theme:ApplyFont(logo, spec.fontRole or "label", M().logoFontSize)
        logo:SetPoint("TOPLEFT", 2, -2)
        logo:SetText(model.ascii)
        logo:SetJustifyH("LEFT")
        logo:SetTextColor(ar, ag, ab, 1)
        logoBtn._logo = logo

        -- Measure with the full logo, since the home state empties the text
        C_Timer.After(0.05, function()
            if logo and logoBtn then
                local currentText = logo:GetText()
                logo:SetText(model.ascii)
                local w = logo:GetStringWidth() or 400
                local h = logo:GetStringHeight() or 40
                logo:SetText(currentText or "")
                logoBtn:SetSize(w + 4, h + 4)
            end
        end)
        logoBtn:SetSize(220, 45)  -- Fallback

        local hoverBg = logoBtn:CreateTexture(nil, "BACKGROUND")
        hoverBg:SetAllPoints()
        hoverBg:SetColorTexture(ar, ag, ab, 1)
        hoverBg:Hide()
        logoBtn._hoverBg = hoverBg

        logoBtn:SetScript("OnEnter", function(btn)
            local r, g, b = Theme:GetAccentColor()
            btn._hoverBg:SetColorTexture(r, g, b, 1)
            btn._hoverBg:Show()
            btn._logo:SetTextColor(0, 0, 0, 1)
        end)
        logoBtn:SetScript("OnLeave", function(btn)
            btn._hoverBg:Hide()
            local r, g, b = Theme:GetAccentColor()
            btn._logo:SetTextColor(r, g, b, 1)
        end)
        logoBtn:SetScript("OnClick", function()
            panel:GoHome()
        end)
        passDrag(logoBtn)

        frame._logoBtn = logoBtn
        frame._logo = logo

        Theme:Subscribe("UIPanel_TitleBar", function(r, g, b)
            if not logoBtn:IsMouseOver() then
                logo:SetTextColor(r, g, b, 1)
            end
            hoverBg:SetColorTexture(r, g, b, 1)
        end)

        function handle:SetHome(isHome)
            if isHome then
                panel:StopAsciiAnimation()
                logo:SetText("")
                logoBtn:EnableMouse(false)
            else
                logoBtn:EnableMouse(true)
            end
        end
        function handle:Reveal(animate)
            if animate then
                panel:AnimateAsciiReveal()
            elseif logo:GetText() == "" then
                logo:SetText(model.ascii)
            end
        end
        function handle:Cleanup()
            Theme:Unsubscribe("UIPanel_TitleBar")
        end
    elseif kind == "texture" then
        local tex = titleBar:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(model.texture)
        tex:SetSize(spec.width or 200, spec.height or 40)
        tex:SetPoint(spec.point or "LEFT", titleBar, spec.point or "LEFT", spec.x or 12, spec.y or 0)
        frame._titleTexture = tex
        function handle:SetHome() end
        function handle:Reveal() end
        function handle:Cleanup() end
    else
        local btn = CreateFrame("Button", BRAND .. "TitleBtn", titleBar)
        btn:RegisterForClicks("AnyUp")
        local fs = btn:CreateFontString(nil, "OVERLAY", spec.fontObject)
        if not spec.fontObject then
            Theme:ApplyFont(fs, spec.fontRole or "header", spec.fontSize or M().home.textSize)
            local ar, ag, ab = Theme:GetAccentColor()
            fs:SetTextColor(ar, ag, ab, 1)
            Theme:Subscribe("UIPanel_TitleBar", function(r, g, b)
                fs:SetTextColor(r, g, b, 1)
            end)
        end
        fs:SetText(model.text or BRAND)
        fs:SetPoint("CENTER")
        local w, h = fs:GetStringWidth() or 0, fs:GetStringHeight() or 0
        btn:SetSize(math.max(w + 8, 60), math.max(h + 8, 20))
        btn:SetPoint(spec.point or "LEFT", titleBar, spec.point or "LEFT", spec.x or 12, spec.y or 0)
        btn:SetScript("OnClick", function()
            panel:GoHome()
        end)
        passDrag(btn)
        frame._titleText = fs

        function handle:SetHome(isHome)
            btn:EnableMouse(not isHome)
        end
        function handle:Reveal() end
        function handle:Cleanup()
            Theme:Unsubscribe("UIPanel_TitleBar")
        end
    end

    return handle
end

-- Go Home (navigate to home, clear nav selection)

function UIPanel:GoHome()
    if Navigation then
        Navigation._selectedKey = nil
        Navigation:UpdateRowColors()
    end

    self:OnNavigationSelect("home", Navigation and Navigation._selectedKey)
end

-- Close Button

function UIPanel:CreateCloseButton()
    local frame = self.frame
    if not frame then return end

    local panel = self
    local closeBtn = Controls:CreateCloseButton({
        parent = frame,
        name = BRAND .. "CloseButton",
        onClick = function()
            if panel and panel.frame then
                panel.frame:Hide()
            end
        end,
    })
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", M().closeButton.x, M().closeButton.y)
    closeBtn:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame._closeBtn = closeBtn
end

-- The toolbar: the product's HeaderModel.toolbar as buttons across the top
-- edge. action.kind "page" selects a nav key, "editMode" opens Blizzard's
-- Edit Mode through a secure click, "call" runs action.fn(panel).

local function WireEditMode(btn)
    local function setup()
        if not C_AddOns.IsAddOnLoaded("Blizzard_EditMode") then
            C_AddOns.LoadAddOn("Blizzard_EditMode")
        end
        if EditModeManagerFrame then
            SecureHandlerSetFrameRef(btn, "em", EditModeManagerFrame)
            btn:SetAttribute("_onclick", [[ self:GetFrameRef("em"):Show() ]])
        end
    end
    if InCombatLockdown() then
        -- Queue on the shared regen drain instead of registering events on the
        -- secure button itself; setup is idempotent.
        addon.Events.RunOutOfCombat(setup, "SettingsPanel:secureEditMode")
    else
        setup()
    end
    btn:HookScript("PostClick", function()
        if addon.EditMode and addon.EditMode.MarkOpeningEditMode then
            addon.EditMode.MarkOpeningEditMode()
        end
    end)
end

function UIPanel:CreateHeaderButtons()
    local frame = self.frame
    if not frame then return end

    local panel = self
    local buttons, byKey = {}, {}

    for _, entry in ipairs(HeaderModel().toolbar or {}) do
        if not entry.isVisible or entry.isVisible() then
            local action = entry.action or {}
            local key = tostring(entry.key or entry.label)
            local opts = {
                parent = frame,
                name = BRAND .. key:sub(1, 1):upper() .. key:sub(2) .. "Btn",
                text = entry.label,
                height = M().toolbar.height,
                fontSize = M().toolbar.fontSize,
            }
            if action.kind == "page" then
                opts.onClick = function()
                    Navigation:SelectItem(action.page)
                end
            elseif action.kind == "editMode" then
                opts.template = "SecureActionButtonTemplate, SecureHandlerClickTemplate"
                opts.secureAction = {}  -- triggers AnyUp registration in Button.lua
            elseif action.kind == "call" and action.fn then
                opts.onClick = function()
                    action.fn(panel)
                end
            end
            local btn = Controls:CreateButton(opts)
            if action.kind == "editMode" then
                WireEditMode(btn)
            end
            btn._entry = entry
            buttons[#buttons + 1] = btn
            byKey[key] = btn
        end
    end

    -- Centered across the top edge, in the skin's spacing and offset
    local function PositionToolbar()
        local totalW = 0
        for _, btn in ipairs(buttons) do
            totalW = totalW + (btn:GetWidth() or 0)
        end
        totalW = totalW + math.max(#buttons - 1, 0) * M().toolbar.spacing

        local startX = -(totalW / 2)
        for _, btn in ipairs(buttons) do
            btn:ClearAllPoints()
            local btnW = btn:GetWidth() or 0
            btn:SetPoint("CENTER", frame, "TOP", startX + (btnW / 2), M().toolbar.y or 0)
            startX = startX + btnW + M().toolbar.spacing
        end
    end

    PositionToolbar()
    frame:HookScript("OnSizeChanged", PositionToolbar)

    local btnLevel = frame:GetFrameLevel() + 15
    for _, btn in ipairs(buttons) do
        btn:SetFrameLevel(btnLevel)
    end

    frame._toolbarOrder = buttons
    frame._toolbarButtons = byKey
    self:RefreshToolbar()
end

-- A page button shows pressed-in while its page is open
function UIPanel:UpdateToolbarActive(pageKey)
    local frame = self.frame
    if not frame or not frame._toolbarOrder then return end
    for _, btn in ipairs(frame._toolbarOrder) do
        local action = btn._entry and btn._entry.action or {}
        btn:SetActive(action.kind == "page" and action.page == pageKey)
    end
end

-- Re-evaluates each entry's pulseWhen
function UIPanel:RefreshToolbar()
    local frame = self.frame
    if not frame or not frame._toolbarOrder then return end
    for _, btn in ipairs(frame._toolbarOrder) do
        local when = btn._entry and btn._entry.pulseWhen
        if when then
            btn:SetPulsing(when() and true or false)
        end
    end
end

-- Resize Handle (bottom-right corner grip)

function UIPanel:CreateResizeHandle()
    local frame = self.frame
    if not frame then return end

    local m = M().resizeGrip
    local spec = Chrome.Spec("resizeGrip")
    local resizeHandle = CreateFrame("Button", BRAND .. "ResizeHandle", frame)
    resizeHandle:SetSize(m.size, m.size)
    resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", m.x, m.y)
    resizeHandle:SetFrameLevel(frame:GetOverlayLevel())
    resizeHandle:EnableMouse(true)

    -- The atlas kind is one texture with a hover swap; flat is the dotted
    -- diagonal, accent-tinted, brighter under the cursor.
    local function paint(handle, hover)
        if handle._art then
            handle._art:SetAtlas((hover and spec.hover) or spec.normal, true)
            handle._art:SetAllPoints(handle)
            return
        end
        local r, g, b = Theme:GetAccentColor()
        local alpha = hover and 1 or m.alpha
        for _, line in ipairs(handle._lines) do
            line:SetColorTexture(r, g, b, alpha)
        end
    end

    if spec.kind == "atlas" then
        local art = resizeHandle:CreateTexture(nil, "OVERLAY")
        art:SetAllPoints()
        resizeHandle._art = art
    else
        local lines = {}
        for i = 1, 3 do
            local line = resizeHandle:CreateTexture(nil, "OVERLAY")
            line:SetSize(m.dot, m.dot)
            local offset = (i - 1) * m.step
            line:SetPoint("BOTTOMRIGHT", resizeHandle, "BOTTOMRIGHT", -offset - m.dot, offset + m.dot)
            lines[i] = line
        end
        for i = 1, 2 do
            local line = resizeHandle:CreateTexture(nil, "OVERLAY")
            line:SetSize(m.dot, m.dot)
            local offset = (i - 1) * m.step
            line:SetPoint("BOTTOMRIGHT", resizeHandle, "BOTTOMRIGHT", -offset - m.dot - m.step, offset + m.dot)
            lines[3 + i] = line
        end
        local cornerDot = resizeHandle:CreateTexture(nil, "OVERLAY")
        cornerDot:SetSize(m.dot, m.dot)
        cornerDot:SetPoint("BOTTOMRIGHT", resizeHandle, "BOTTOMRIGHT", -m.dot, m.dot + m.step)
        lines[6] = cornerDot
        resizeHandle._lines = lines
    end
    paint(resizeHandle, false)

    resizeHandle:SetScript("OnEnter", function(handle)
        paint(handle, true)
        SetCursor("Interface\\CURSOR\\UI-Cursor-Size")
    end)

    resizeHandle:SetScript("OnLeave", function(handle)
        paint(handle, false)
        ResetCursor()
    end)

    resizeHandle:SetScript("OnMouseDown", function(handle, button)
        if button == "LeftButton" then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)

    resizeHandle:SetScript("OnMouseUp", function(handle, button)
        frame:StopMovingOrSizing()
        if addon.db and addon.db.global then
            local width, height = frame:GetSize()
            addon.db.global.windowSize = {
                width = width,
                height = height
            }
        end
    end)

    frame._resizeHandle = resizeHandle

    Theme:Subscribe("UIPanel_ResizeHandle", function()
        if not resizeHandle:IsMouseOver() then
            paint(resizeHandle, false)
        end
    end)
end

-- Navigation Sidebar

function UIPanel:CreateNavigation()
    local frame = self.frame
    if not frame then return end

    local navFrame = Navigation:Create(frame)
    if navFrame then
        frame._navigation = navFrame

        Navigation:SetOnSelectCallback(function(key, previousKey)
            self:OnNavigationSelect(key, previousKey)
        end)
    end
end

-- Content Pane

function UIPanel:CreateContentPane()
    local frame = self.frame
    if not frame then return end

    local contentPane = CreateFrame("Frame", BRAND .. "ContentPane", frame)
    local inset = M().windowInset
    contentPane:SetPoint("TOPLEFT", frame, "TOPLEFT", M().navWidth + inset + M().nav.dividerWidth, -(M().titleBarHeight))
    contentPane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)

    local header = CreateFrame("Frame", nil, contentPane)
    header:SetHeight(M().contentHeaderHeight)
    header:SetPoint("TOPLEFT", contentPane, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", contentPane, "TOPRIGHT", 0, 0)

    local headerTitle = header:CreateFontString(nil, "OVERLAY")
    Theme:ApplyHeaderFont(headerTitle, 20)
    headerTitle:SetPoint("TOPLEFT", header, "TOPLEFT", 16, -10)
    headerTitle:SetText("Home")  -- Default
    contentPane._headerTitle = headerTitle

    local headerSubtitle = header:CreateFontString(nil, "OVERLAY")
    Theme:ApplyFont(headerSubtitle, "label", 11)
    local sr, sg, sb = Theme:GetAccentColor()
    headerSubtitle:SetTextColor(sr, sg, sb, 0.5)
    headerSubtitle:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 16, 8)
    headerSubtitle:Hide()
    contentPane._headerSubtitle = headerSubtitle

    local defaultsBtn = Controls:CreateButton({
        parent = header,
        name = BRAND .. "DefaultsBtn",
        text = "Defaults",
        height = 17,
        fontSize = 10,
        borderWidth = 1,
        borderAlpha = 0.6,
        onClick = function()
            local settingsPanel = addon.UI and addon.UI.SettingsPanel
            if settingsPanel and settingsPanel.HandleDefaultsClick then
                settingsPanel:HandleDefaultsClick()
            end
        end,
    })
    defaultsBtn:Hide()
    contentPane._defaultsBtn = defaultsBtn

    local defaultsInfoIcon = Controls:CreateInfoIcon({
        parent = header,
        tooltipTitle = "Reset to Defaults",
        tooltipText = "Resets all settings and position for this category to Blizzard defaults. User-curated content (Custom Group spell lists, group names) is preserved.\n\nRequires a UI reload. This action cannot be undone.",
        size = 12,
    })
    if defaultsInfoIcon then
        defaultsInfoIcon:Hide()
        contentPane._defaultsInfoIcon = defaultsInfoIcon
    end

    local panel = self
    local collapseAllBtn = Controls:CreateButton({
        parent = header,
        name = BRAND .. "CollapseAllBtn",
        text = "Collapse All",
        height = 17,
        fontSize = 10,
        borderWidth = 1,
        borderAlpha = 0.6,
        onClick = function(btn, mouseButton)
            panel:CollapseAllSections()
        end
    })
    collapseAllBtn:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, 8)
    collapseAllBtn:Hide()  -- Hidden by default, shown when collapsible sections exist
    contentPane._collapseAllBtn = collapseAllBtn

    local copyFromDropdown = Controls:CreateDropdown({
        parent = header,
        name = BRAND .. "CopyFromDropdown",
        values = {},  -- Will be populated dynamically
        placeholder = "Select...",
        width = 140,
        height = 22,
        fontSize = 11,
        set = function(sourceKey)
            panel:HandleCopyFrom(sourceKey)
        end,
    })
    copyFromDropdown:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, -9)
    copyFromDropdown:Hide()  -- Hidden by default, shown for Action Bar categories
    contentPane._copyFromDropdown = copyFromDropdown

    local copyFromLabel = header:CreateFontString(nil, "OVERLAY")
    Theme:ApplyFont(copyFromLabel, "label", 11)
    copyFromLabel:SetText("Copy from:")
    local ar, ag, ab = Theme:GetAccentColor()
    copyFromLabel:SetTextColor(ar, ag, ab, 0.8)
    copyFromLabel:SetPoint("RIGHT", copyFromDropdown, "LEFT", -8, 0)
    copyFromLabel:Hide()  -- Hidden by default
    contentPane._copyFromLabel = copyFromLabel

    local headerSep = header:CreateTexture(nil, "BORDER")
    headerSep:SetHeight(1)
    headerSep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 8, 0)
    headerSep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, 0)
    headerSep:SetColorTexture(ar, ag, ab, 0.3)
    contentPane._headerSep = headerSep
    contentPane._header = header
    -- A page that grows the header (the Aura List, to fit its wrapped how-to
    -- line) restores this through UIPanel:ResetHeaderSubtitle.
    contentPane._headerBaseHeight = M().contentHeaderHeight

    local scrollFrame = CreateFrame("ScrollFrame", BRAND .. "ContentScrollFrame", contentPane)
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", M().paneInset, -M().paneInset)
    scrollFrame:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -(M().scrollBar.margin + M().scrollBar.width + M().paneInset), M().paneInset)
    scrollFrame:EnableMouseWheel(true)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local scrollChild = self:GetScrollChild()
        local contentHeight = scrollChild and scrollChild:GetHeight() or 0
        local visibleHeight = self:GetHeight() or 1
        local maxScroll = math.max(0, contentHeight - visibleHeight)

        local step = 60  -- Pixels per scroll
        local newScroll = current - (delta * step)
        newScroll = math.max(0, math.min(maxScroll, newScroll))

        self:SetVerticalScroll(newScroll)

        if contentPane._scrollbar and contentPane._scrollbar.Sync then
            contentPane._scrollbar:Sync()
        end
    end)

    local scrollContent = CreateFrame("Frame", BRAND .. "ContentScrollContent", scrollFrame)
    local sfWidth = scrollFrame:GetWidth()
    scrollContent:SetWidth((sfWidth and sfWidth > 0) and (sfWidth - 16) or 400)
    scrollFrame:SetScrollChild(scrollContent)
    contentPane._scrollFrame = scrollFrame
    contentPane._scrollContent = scrollContent

    local scrollbar = Controls.CreateScrollBar({ parent = contentPane, scrollFrame = scrollFrame })
    -- Hung from the header rather than a fixed offset from the pane, so it
    -- follows a header a page has grown.
    scrollbar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -M().scrollBar.margin, -M().paneInset)
    scrollbar:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -M().scrollBar.margin, (M().resizeGrip.size + M().scrollBar.margin))
    contentPane._scrollbar = scrollbar

    local placeholder = scrollContent:CreateFontString(nil, "OVERLAY")
    Theme:ApplyDimFont(placeholder, 13)
    placeholder:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 8, -16)
    placeholder:SetWidth(500)
    placeholder:SetJustifyH("LEFT")
    placeholder:SetText("")
    placeholder:Hide()  -- Start hidden (Home page is blank)
    contentPane._placeholder = placeholder

    local homeContent = CreateFrame("Frame", BRAND .. "HomeContent", contentPane)
    homeContent:SetAllPoints(contentPane)

    local homeContainer = CreateFrame("Frame", nil, homeContent)
    homeContainer:SetPoint("CENTER", homeContent, "CENTER", 0, 80)  -- Shifted up to make room for Feature Guide

    local title = HeaderModel().title or {}
    local homeAscii = homeContainer:CreateFontString(nil, "OVERLAY")
    Theme:ApplyFont(homeAscii, "label", M().home.logoFontSize)
    homeAscii:SetText(title.ascii or title.text or BRAND)
    homeAscii:SetJustifyH("LEFT")
    homeAscii:SetTextColor(ar, ag, ab, 1)
    homeAscii:SetPoint("CENTER", homeContainer, "CENTER", 0, 0)

    local versionText = homeContainer:CreateFontString(nil, "OVERLAY")
    Theme:ApplyFont(versionText, "label", M().home.textSize)
    versionText:SetTextColor(ar, ag, ab, 1)
    do
        local ver
        if C_AddOns and C_AddOns.GetAddOnMetadata then
            local ok, v = pcall(C_AddOns.GetAddOnMetadata, addonName, "Version")
            if ok and v then ver = v end
        end
        versionText:SetText("v" .. (ver or "?.?.?"))
    end
    versionText:SetPoint("BOTTOMLEFT", homeAscii, "BOTTOMRIGHT", -2, 0)

    local homeMascot = homeContainer:CreateFontString(nil, "OVERLAY")
    Theme:ApplyFont(homeMascot, "label", M().home.mascotFontSize)
    homeMascot:SetText(title.mascot or "")
    homeMascot:SetJustifyH("LEFT")
    homeMascot:SetTextColor(ar, ag, ab, 1)
    local welcomeText = homeContainer:CreateFontString(nil, "OVERLAY")
    Theme:ApplyFont(welcomeText, "label", M().home.textSize)
    welcomeText:SetText("Welcome to")
    welcomeText:SetTextColor(1, 1, 1, 1)
    homeMascot:SetPoint("BOTTOM", homeAscii, "TOP", 37, 8)
    welcomeText:SetPoint("BOTTOMRIGHT", homeMascot, "BOTTOMLEFT", 20, 0)
    if not title.mascot then
        homeMascot:Hide()
        welcomeText:Hide()
    end

    C_Timer.After(0.05, function()
        if homeAscii and homeMascot and homeContainer then
            local titleW = homeAscii:GetStringWidth() or 600
            local titleH = homeAscii:GetStringHeight() or 80
            local mascotW = homeMascot:GetStringWidth() or 200
            local mascotH = homeMascot:GetStringHeight() or 150
            homeContainer:SetSize(math.max(titleW, mascotW), titleH + mascotH + 16)
        end
    end)
    homeContainer:SetSize(450, 150)  -- Fallback


    local guideDivider = homeContent:CreateTexture(nil, "BORDER")
    guideDivider:SetHeight(1)
    guideDivider:SetPoint("TOPLEFT", homeAscii, "BOTTOMLEFT", -M().home.guideInset, -10)
    guideDivider:SetPoint("TOPRIGHT", homeAscii, "BOTTOMRIGHT", M().home.guideInset, -10)
    guideDivider:SetColorTexture(ar, ag, ab, 0.3)

    local guideHeader = homeContent:CreateFontString(nil, "OVERLAY")
    Theme:ApplyFont(guideHeader, "header", 20)
    guideHeader:SetText("Feature Guide:")
    guideHeader:SetTextColor(ar, ag, ab, 1)
    guideHeader:SetPoint("TOP", guideDivider, "BOTTOM", 0, -8)

    local guideIcons = {}
    local guideLabels = {}

    -- Shared X/Y/Z descriptions live in core/modules.lua (addon.FEATURE_GUIDE);
    -- the Features page legend renders from the same table.
    for i, entry in ipairs(addon.FEATURE_GUIDE or {}) do
        local icon = Controls:CreateInfoIcon({
            parent = homeContent,
            size = M().home.guideIconSize,
            customText = entry.letter,
            colorOverride = entry.color,
            tooltipTitle = entry.tooltipTitle,
            tooltipText = entry.tooltipText,
        })
        -- Center the icon under the header for the first row; anchor later rows
        -- below the previous row's text so spacing tracks the wrapped height
        if i == 1 then
            icon:SetPoint("TOP", guideHeader, "BOTTOM", -(M().home.guideTextWidth / 2) - (M().home.guideIconSize / 2), -11)
        else
            icon:SetPoint("TOPLEFT", guideLabels[i - 1], "BOTTOMLEFT", -(M().home.guideIconSize + M().home.guideIconTextGap), -M().home.guideRowSpacing)
        end

        local summaryText = homeContent:CreateFontString(nil, "OVERLAY")
        Theme:ApplyFont(summaryText, "label", M().home.guideTextSize)
        local cr, cg, cb = entry.color[1], entry.color[2], entry.color[3]
        summaryText:SetTextColor(cr, cg, cb, 0.55)
        summaryText:SetText(entry.summary)
        summaryText:SetJustifyH("LEFT")
        summaryText:SetWordWrap(true)
        summaryText:SetWidth(M().home.guideTextWidth)
        summaryText:SetPoint("TOPLEFT", icon, "TOPRIGHT", M().home.guideIconTextGap, -2)

        guideIcons[i] = icon
        guideLabels[i] = summaryText
    end

    -- Accent color control, pinned into the bottom-left corner of the home page.
    -- The flyout opens downward, past the panel's bottom edge.
    local accentControl = Controls:CreateFlyoutColorPicker({
        parent = homeContent,
        name = BRAND .. "AccentColorPicker",
        label = "UI Color",
        direction = "DOWN",
        width = 280,
        get = function() return Theme:GetCustomAccentColor() end,
        set = function(r, g, b) Theme:SetAccentColor(r, g, b, 1) end,
        preview = function() return Theme:GetAccentColor() end,
        colorLabel = "Custom Color",
        colorDisabled = function()
            return Theme:GetAccentColorMode() == Theme.ACCENT_MODE_CLASS
        end,
        toggleLabel = "Class Color",
        toggleGet = function()
            return Theme:GetAccentColorMode() == Theme.ACCENT_MODE_CLASS
        end,
        toggleSet = function(value)
            Theme:SetAccentColorMode(value and Theme.ACCENT_MODE_CLASS or Theme.ACCENT_MODE_CUSTOM)
        end,
        resetLabel = "Reset to Default",
        onReset = function() Theme:ResetAccentColor() end,
    })
    if accentControl then
        accentControl:SetPoint("BOTTOMLEFT", homeContent, "BOTTOMLEFT",
            M().home.accentInset, M().home.accentInset)
        homeContent._accentControl = accentControl
    end

    homeContent._guideIcons = guideIcons
    homeContent._guideLabels = guideLabels
    homeContent._guideDivider = guideDivider
    homeContent._guideHeader = guideHeader

    homeContent._welcomeText = welcomeText
    homeContent._asciiLogo = homeAscii
    homeContent._asciiMascot = homeMascot
    homeContent._versionText = versionText
    contentPane._homeContent = homeContent

    Theme:Subscribe("UIPanel_HomeContent", function(r, g, b)
        if homeAscii then
            homeAscii:SetTextColor(r, g, b, 1)
        end
        if guideDivider then
            guideDivider:SetColorTexture(r, g, b, 0.3)
        end
        if guideHeader then
            guideHeader:SetTextColor(r, g, b, 1)
        end
        if homeMascot then
            homeMascot:SetTextColor(r, g, b, 1)
        end
        if versionText then
            versionText:SetTextColor(r, g, b, 1)
        end
    end)

    frame._contentPane = contentPane

    -- Home state: header hidden, ASCII logo hidden, home content shown
    headerTitle:Hide()
    headerSep:Hide()
    scrollFrame:SetPoint("TOPLEFT", contentPane, "TOPLEFT", M().paneInset, -M().paneInset)
    homeContent:Show()  -- Show home content by default

    if frame._logo then
        frame._logo:SetText("")
    end
    if frame._logoBtn then
        frame._logoBtn:EnableMouse(false)
    end

    Theme:Subscribe("UIPanel_ContentPane", function(r, g, b)
        if contentPane._headerSep then
            contentPane._headerSep:SetColorTexture(r, g, b, 0.3)
        end
        if contentPane._headerTitle then
            contentPane._headerTitle:SetTextColor(r, g, b, 1)
        end
        -- A page that owns the subtitle's color (Aura List: gray) keeps it.
        if contentPane._headerSubtitle and not contentPane._headerSubtitleCustom then
            contentPane._headerSubtitle:SetTextColor(r, g, b, 0.5)
        end
        if contentPane._copyFromLabel then
            contentPane._copyFromLabel:SetTextColor(r, g, b, 0.8)
        end
    end)

    frame:HookScript("OnSizeChanged", function()
        if scrollFrame and scrollContent then
            local width = scrollFrame:GetWidth()
            if width and width > 0 then
                -- Pages that pan horizontally (e.g. Features) declare a minimum
                -- content width; never clamp the scroll child below it
                scrollContent:SetWidth(math.max(width - 16, contentPane._minContentWidth or 0))
            end
        end
        -- A page whose layout reads the window's width at render (the Aura
        -- List) rebuilds itself from this slot once the drag settles. Every
        -- other page re-renders through the navigation dispatch: rows wrap
        -- their text against the width they were built with, so the page must
        -- rebuild at the new width. Debounced so a drag renders once, with
        -- the scroll offset carried over.
        if contentPane._onResize then
            contentPane._onResize()
        else
            local token = (contentPane._resizeToken or 0) + 1
            contentPane._resizeToken = token
            C_Timer.After(0.2, function()
                if contentPane._resizeToken ~= token then return end
                local key = UIPanel._currentCategoryKey
                if key and UIPanel.frame and UIPanel.frame:IsShown() then
                    local scrollOffset = contentPane._scrollFrame
                        and contentPane._scrollFrame:GetVerticalScroll()
                    UIPanel:OnNavigationSelect(key)
                    if scrollOffset and scrollOffset > 0 and contentPane._scrollFrame then
                        contentPane._scrollFrame:SetVerticalScroll(scrollOffset)
                    end
                end
            end)
        end
        if scrollbar and scrollbar.Sync then
            C_Timer.After(0.05, function()
                scrollbar:Sync()
            end)
        end
    end)

    -- Initial scrollbar update
    C_Timer.After(0.1, function()
        if scrollbar and scrollbar.Sync then
            scrollbar:Sync()
        end
    end)
end

-- Teardown

-- Takes the panel back to nothing built, so the next Show rebuilds it from the
-- window out. Skin.SetActive takes this path on a runtime switch and nothing
-- else does. The frame keeps its global name, so the UISpecialFrames entry
-- resolves to the rebuilt frame.
function UIPanel:Teardown()
    local frame = self.frame
    if not frame then return end

    self:StopAsciiAnimation()
    frame:Hide()

    if Navigation and Navigation.Cleanup then
        Navigation:Cleanup()
    end

    for _, btn in ipairs(frame._toolbarOrder or {}) do
        if btn.Cleanup then btn:Cleanup() end
    end
    if frame._closeBtn and frame._closeBtn.Cleanup then frame._closeBtn:Cleanup() end
    if frame._title and frame._title.Cleanup then frame._title:Cleanup() end
    local contentPane = frame._contentPane
    if contentPane then
        for _, btn in ipairs({ contentPane._defaultsBtn, contentPane._collapseAllBtn }) do
            if btn and btn.Cleanup then btn:Cleanup() end
        end
        if contentPane._scrollbar and contentPane._scrollbar.Cleanup then
            contentPane._scrollbar:Cleanup()
        end
    end
    for _, key in ipairs({ "UIPanel_ResizeHandle", "UIPanel_HomeContent", "UIPanel_ContentPane" }) do
        Theme:Unsubscribe(key)
    end

    Window:Destroy(frame)

    self.frame = nil
    self._initialized = false
    self._currentCategoryKey = nil
    self._currentBuilder = nil
end

-- Public API

function UIPanel:Toggle()
    if InCombatLockdown and InCombatLockdown() then
        -- Message already shown when panel was closed; don't spam
        return
    end

    if not self._initialized then
        self:Initialize()
    end

    if self.frame then
        if self.frame:IsShown() then
            self:Hide()
        else
            self:Show()  -- Ensures category re-render
        end
    end
end

function UIPanel:Show()
    if InCombatLockdown and InCombatLockdown() then
        -- Message already shown when panel was closed; don't spam
        return
    end

    if not self._initialized then
        self:Initialize()
    end

    if self.frame then
        -- Sync all Edit Mode values to component.db before rendering
        if addon and addon.EditMode and addon.EditMode.RefreshSyncAndNotify then
            addon.EditMode.RefreshSyncAndNotify("OpenPanel")
        end

        self.frame:Show()

        if Navigation and Navigation.Rebuild then
            Navigation:Rebuild()
        end

        -- Re-render the current category to reflect any Edit Mode changes
        local currentKey = self._currentCategoryKey
        if currentKey and currentKey ~= "home" then
            self._pendingBackSync[currentKey] = nil
            C_Timer.After(0, function()
                -- Self-cancel if something navigated away in the meantime.
                -- addon.UI:OpenToPage calls Show() then SelectItem() in the same
                -- frame; OnNavigationSelect sets _currentCategoryKey synchronously,
                -- so this guard has already flipped by the time the timer runs.
                -- Removing it makes every deep link land on the previous page.
                if self.frame and self.frame:IsShown()
                    and self._currentCategoryKey == currentKey then
                    self:OnNavigationSelect(currentKey, currentKey)
                end
            end)
        end
    end
end

function UIPanel:Hide()
    -- Stop any running ASCII animation before hiding
    self:StopAsciiAnimation()

    if self.frame then
        self.frame:Hide()
    end
end

function UIPanel:IsShown()
    return self.frame and self.frame:IsShown()
end

-- Combat Safety (auto-close on combat start, auto-reopen on combat end)

UIPanel._closedByCombat = false

local function onCombatEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        if UIPanel.frame and UIPanel.frame:IsShown() then
            UIPanel._closedByCombat = true
            UIPanel.frame:Hide()
            if addon and addon.Print then
                addon:Print(BRAND .. " settings will reopen when combat ends.")
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if UIPanel._closedByCombat then
            UIPanel._closedByCombat = false
            C_Timer.After(0.1, function()
                if not InCombatLockdown() then
                    UIPanel:Show()
                end
            end)
        end
    end
end

addon.Events.On("UI:SettingsPanel", "PLAYER_REGEN_DISABLED", onCombatEvent)
addon.Events.On("UI:SettingsPanel", "PLAYER_REGEN_ENABLED", onCombatEvent)

