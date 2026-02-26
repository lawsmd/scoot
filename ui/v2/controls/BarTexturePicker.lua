-- BarTexturePicker.lua - Bar texture selection popup with tabbed categories
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme -- Will be set after Theme.lua loads

-- Lazy Theme accessor
local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local PICKER_WIDTH = 620
local PICKER_HEIGHT = 420
local TAB_WIDTH = 90
local TAB_HEIGHT = 32
local TITLE_HEIGHT = 30
local PADDING = 12

-- 3-column grid layout
local TEXTURES_PER_ROW = 3
local TEXTURE_BUTTON_WIDTH = 160
local TEXTURE_BUTTON_HEIGHT = 46  -- Height for name + preview with clear gap
local TEXTURE_BUTTON_SPACING = 6  -- Vertical spacing between items
local PREVIEW_WIDTH = 100
local PREVIEW_HEIGHT = 16

-- Fallback brand colors
local BRAND_R, BRAND_G, BRAND_B = 0.20, 0.90, 0.30

--------------------------------------------------------------------------------
-- Texture Categories (per design doc)
--------------------------------------------------------------------------------

local STANDARD_TEXTURES = {
    "default",  -- Special case: restores stock appearance
    "a1", "a2", "a3",
    "bevelled", "bevelledGrey",
    "fadeTop", "fadeBottom", "fadeLeft",
}

local BLIZZARD_TEXTURES = {
    "blizzardCastBar",
    "blizzardEbonMight", "blizzardEnergy", "blizzardFocus", "blizzardFury",
    "blizzardInsanity", "blizzardInsanity2", "blizzardLunarPower",
    "blizzardMaelstrom", "blizzardMana", "blizzardPain", "blizzardPain2",
    "blizzardPain3", "blizzardRage", "blizzardRaidBar", "blizzardRunicPower",
    "blizzardUnitframe7", "blizzardUnitframe8",
    "blizzardExperience1", "blizzardExperience2", "blizzardExperience3",
    "blizzardLabs1", "blizzardLabs2",
}

local TABS = {
    { key = "standard", label = "Standard", textures = STANDARD_TEXTURES },
    { key = "blizzard", label = "Blizzard", textures = BLIZZARD_TEXTURES },
}

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------

local pickerFrame = nil
local pickerSetting = nil
local pickerCallback = nil
local pickerAnchor = nil
local selectedTab = "standard"

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

local function GetTextureDisplayName(key, stripBlizzardPrefix)
    local name = key
    if addon.Media and addon.Media.GetBarTextureDisplayName then
        local displayName = addon.Media.GetBarTextureDisplayName(key)
        if displayName and displayName ~= "" then
            name = displayName
        end
    end
    if key == "default" then return "Default (Stock)" end
    -- Strip "Blizzard " prefix when requested (for Blizzard tab to avoid redundancy)
    if stripBlizzardPrefix and name:sub(1, 9) == "Blizzard " then
        name = name:sub(10)
    end
    return name
end

local function GetTexturePath(key)
    if addon.Media and addon.Media.ResolveBarTexturePath then
        return addon.Media.ResolveBarTexturePath(key)
    end
end

local function GetCategoryForTexture(textureKey)
    for _, key in ipairs(STANDARD_TEXTURES) do
        if key == textureKey then return "standard" end
    end
    for _, key in ipairs(BLIZZARD_TEXTURES) do
        if key == textureKey then return "blizzard" end
    end
    return "standard"  -- Default fallback
end

--------------------------------------------------------------------------------
-- Picker Frame Creation
--------------------------------------------------------------------------------

local function CloseBarTexturePicker()
    if pickerFrame then
        pickerFrame:Hide()
    end
    pickerSetting = nil
    pickerCallback = nil
    pickerAnchor = nil
end

local function CreateBarTexturePicker()
    if pickerFrame then return pickerFrame end

    local theme = GetTheme()
    local accentR, accentG, accentB = BRAND_R, BRAND_G, BRAND_B
    if theme and theme.GetAccentColor then
        accentR, accentG, accentB = theme:GetAccentColor()
    end

    -- Calculate content area width
    local contentWidth = (TEXTURE_BUTTON_WIDTH * TEXTURES_PER_ROW) + (TEXTURE_BUTTON_SPACING * (TEXTURES_PER_ROW - 1)) + (PADDING * 2)
    local totalWidth = TAB_WIDTH + contentWidth + 24 -- Extra for scrollbar

    local frame = CreateFrame("Frame", "ScootBarTexturePickerFrame", UIParent)
    frame:SetSize(totalWidth, PICKER_HEIGHT)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Background (TUI dark)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.06, 0.96)
    frame._bg = bg

    -- Border (accent color)
    local borderWidth = 1
    local borders = {}

    local topBorder = frame:CreateTexture(nil, "BORDER", nil, -1)
    topBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    topBorder:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    topBorder:SetHeight(borderWidth)
    topBorder:SetColorTexture(accentR, accentG, accentB, 0.8)
    borders.TOP = topBorder

    local bottomBorder = frame:CreateTexture(nil, "BORDER", nil, -1)
    bottomBorder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetHeight(borderWidth)
    bottomBorder:SetColorTexture(accentR, accentG, accentB, 0.8)
    borders.BOTTOM = bottomBorder

    local leftBorder = frame:CreateTexture(nil, "BORDER", nil, -1)
    leftBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -borderWidth)
    leftBorder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, borderWidth)
    leftBorder:SetWidth(borderWidth)
    leftBorder:SetColorTexture(accentR, accentG, accentB, 0.8)
    borders.LEFT = leftBorder

    local rightBorder = frame:CreateTexture(nil, "BORDER", nil, -1)
    rightBorder:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -borderWidth)
    rightBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, borderWidth)
    rightBorder:SetWidth(borderWidth)
    rightBorder:SetColorTexture(accentR, accentG, accentB, 0.8)
    borders.RIGHT = rightBorder

    frame._borders = borders

    -- Title
    local titleFont = (theme and theme.GetFont and theme:GetFont("HEADER")) or "Fonts\\FRIZQT__.TTF"
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont(titleFont, 14, "")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -10)
    title:SetText("Select Bar Texture")
    title:SetTextColor(1, 1, 1, 1)
    frame.Title = title

    -- Close button (X)
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    closeBtn:EnableMouse(true)
    closeBtn:RegisterForClicks("AnyUp")

    local closeBtnBg = closeBtn:CreateTexture(nil, "BACKGROUND", nil, -7)
    closeBtnBg:SetAllPoints()
    closeBtnBg:SetColorTexture(accentR, accentG, accentB, 1)
    closeBtnBg:Hide()
    closeBtn._bg = closeBtnBg

    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY")
    closeBtnText:SetFont(titleFont, 14, "")
    closeBtnText:SetPoint("CENTER", 0, 0)
    closeBtnText:SetText("X")
    closeBtnText:SetTextColor(accentR, accentG, accentB, 1)
    closeBtn._text = closeBtnText

    closeBtn:SetScript("OnEnter", function(self)
        self._bg:Show()
        self._text:SetTextColor(0, 0, 0, 1)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self._bg:Hide()
        self._text:SetTextColor(accentR, accentG, accentB, 1)
    end)
    closeBtn:SetScript("OnClick", CloseBarTexturePicker)
    frame.CloseButton = closeBtn

    -- Tab container (left side)
    local tabContainer = CreateFrame("Frame", nil, frame)
    tabContainer:SetSize(TAB_WIDTH, PICKER_HEIGHT - TITLE_HEIGHT - PADDING * 2)
    tabContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -(TITLE_HEIGHT + 4))
    frame.TabContainer = tabContainer

    -- Vertical separator between tabs and content
    local tabSep = frame:CreateTexture(nil, "BORDER", nil, 0)
    tabSep:SetWidth(1)
    tabSep:SetPoint("TOPLEFT", tabContainer, "TOPRIGHT", 4, 0)
    tabSep:SetPoint("BOTTOMLEFT", tabContainer, "BOTTOMRIGHT", 4, 0)
    tabSep:SetColorTexture(accentR, accentG, accentB, 0.4)
    frame._tabSep = tabSep

    -- Tab buttons
    frame.TabButtons = {}
    local labelFont = (theme and theme.GetFont and theme:GetFont("LABEL")) or "Fonts\\FRIZQT__.TTF"

    for i, tabData in ipairs(TABS) do
        local tabBtn = CreateFrame("Button", nil, tabContainer)
        tabBtn:SetSize(TAB_WIDTH, TAB_HEIGHT)
        tabBtn:SetPoint("TOPLEFT", tabContainer, "TOPLEFT", 0, -((i - 1) * TAB_HEIGHT))
        tabBtn:EnableMouse(true)
        tabBtn:RegisterForClicks("AnyUp")

        -- Tab background
        local tabBg = tabBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
        tabBg:SetAllPoints()
        tabBg:SetColorTexture(0.06, 0.06, 0.08, 1)
        tabBtn._bg = tabBg

        -- Left indicator (shown when selected)
        local indicator = tabBtn:CreateTexture(nil, "OVERLAY", nil, 1)
        indicator:SetSize(2, TAB_HEIGHT)
        indicator:SetPoint("LEFT", tabBtn, "LEFT", 0, 0)
        indicator:SetColorTexture(accentR, accentG, accentB, 1)
        indicator:Hide()
        tabBtn._indicator = indicator

        -- Tab label
        local tabLabel = tabBtn:CreateFontString(nil, "OVERLAY")
        tabLabel:SetFont(labelFont, 11, "")
        tabLabel:SetPoint("CENTER", tabBtn, "CENTER", 2, 0)
        tabLabel:SetText(tabData.label)
        tabLabel:SetTextColor(0.6, 0.6, 0.6, 1)  -- Dim when unselected
        tabBtn._label = tabLabel

        tabBtn._key = tabData.key
        tabBtn._textures = tabData.textures

        -- Hover effects
        tabBtn:SetScript("OnEnter", function(self)
            if selectedTab ~= self._key then
                self._bg:SetColorTexture(accentR, accentG, accentB, 0.15)
            end
        end)
        tabBtn:SetScript("OnLeave", function(self)
            if selectedTab ~= self._key then
                self._bg:SetColorTexture(0.06, 0.06, 0.08, 1)
            end
        end)

        -- Click to switch tab
        tabBtn:SetScript("OnClick", function(self)
            if selectedTab ~= self._key then
                selectedTab = self._key
                frame:UpdateTabVisuals()
                frame:PopulateContent()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end
        end)

        frame.TabButtons[tabData.key] = tabBtn
    end

    -- Content area (scroll frame, right of tabs)
    local scrollFrame = CreateFrame("ScrollFrame", "ScootBarTexturePickerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", tabContainer, "TOPRIGHT", 12, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(PADDING + 20), PADDING)
    frame.ScrollFrame = scrollFrame

    -- Style the scrollbar
    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 16)

        -- Hide default textures
        if scrollBar.Background then scrollBar.Background:Hide() end
        if scrollBar.Track then
            if scrollBar.Track.Begin then scrollBar.Track.Begin:Hide() end
            if scrollBar.Track.End then scrollBar.Track.End:Hide() end
            if scrollBar.Track.Middle then scrollBar.Track.Middle:Hide() end
        end

        -- Custom track background
        local trackBg = scrollBar:CreateTexture(nil, "BACKGROUND", nil, -8)
        trackBg:SetPoint("TOPLEFT", 4, 0)
        trackBg:SetPoint("BOTTOMRIGHT", -4, 0)
        trackBg:SetColorTexture(accentR, accentG, accentB, 0.15)
        scrollBar._trackBg = trackBg

        -- Style the thumb
        local thumb = scrollBar.ThumbTexture or scrollBar:GetThumbTexture()
        if thumb then
            thumb:SetColorTexture(accentR, accentG, accentB, 0.6)
            thumb:SetSize(8, 40)
        end

        -- Hide up/down buttons
        local upBtn = scrollBar.ScrollUpButton or scrollBar.Back or _G[scrollBar:GetName() .. "ScrollUpButton"]
        local downBtn = scrollBar.ScrollDownButton or scrollBar.Forward or _G[scrollBar:GetName() .. "ScrollDownButton"]
        if upBtn then upBtn:SetAlpha(0) upBtn:EnableMouse(false) end
        if downBtn then downBtn:SetAlpha(0) downBtn:EnableMouse(false) end

        -- Store reference for visibility toggling
        frame._scrollBar = scrollBar
    end

    -- Content frame (scroll child)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(contentWidth - PADDING, 100)  -- Height will be adjusted dynamically
    scrollFrame:SetScrollChild(content)
    frame.Content = content

    -- Button pool for texture options
    frame.TextureButtons = {}

    -- Store accent colors
    frame._accentR = accentR
    frame._accentG = accentG
    frame._accentB = accentB

    -- Update tab visuals function
    function frame:UpdateTabVisuals()
        for key, tabBtn in pairs(self.TabButtons) do
            local isSelected = (selectedTab == key)
            if isSelected then
                tabBtn._indicator:Show()
                tabBtn._label:SetTextColor(1, 1, 1, 1)
                tabBtn._bg:SetColorTexture(self._accentR, self._accentG, self._accentB, 0.2)
            else
                tabBtn._indicator:Hide()
                tabBtn._label:SetTextColor(0.6, 0.6, 0.6, 1)
                tabBtn._bg:SetColorTexture(0.06, 0.06, 0.08, 1)
            end
        end
    end

    -- Populate content function
    function frame:PopulateContent()
        local currentTab = nil
        for _, tabData in ipairs(TABS) do
            if tabData.key == selectedTab then
                currentTab = tabData
                break
            end
        end
        if not currentTab then return end

        local textures = currentTab.textures
        local content = self.Content
        local valueFont = (theme and theme.GetFont and theme:GetFont("VALUE")) or "Fonts\\FRIZQT__.TTF"

        -- Get current value
        local currentValue = nil
        if pickerSetting and pickerSetting.GetValue then
            currentValue = pickerSetting:GetValue()
        end

        -- Calculate content height
        local numRows = math.ceil(#textures / TEXTURES_PER_ROW)
        local contentHeight = (numRows * TEXTURE_BUTTON_HEIGHT) + ((numRows - 1) * TEXTURE_BUTTON_SPACING) + PADDING
        content:SetHeight(contentHeight)

        -- Show/hide scrollbar based on whether content needs scrolling
        local scrollFrame = self.ScrollFrame
        local scrollBar = self._scrollBar
        if scrollBar and scrollFrame then
            local visibleHeight = scrollFrame:GetHeight()
            if contentHeight > visibleHeight then
                scrollBar:Show()
                if scrollBar._trackBg then scrollBar._trackBg:Show() end
            else
                scrollBar:Hide()
                if scrollBar._trackBg then scrollBar._trackBg:Hide() end
            end
        end

        -- Hide all existing buttons first
        for _, btn in ipairs(self.TextureButtons) do
            btn:Hide()
        end

        -- Create/reuse buttons for each texture option
        for i, textureKey in ipairs(textures) do
            local btn = self.TextureButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, content)
                btn:SetSize(TEXTURE_BUTTON_WIDTH, TEXTURE_BUTTON_HEIGHT)
                btn:EnableMouse(true)
                btn:RegisterForClicks("AnyUp")

                -- Hover background
                local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                btnBg:SetColorTexture(0, 0, 0, 0)
                btn._bg = btnBg

                -- Texture name (positioned at top with padding)
                local nameText = btn:CreateFontString(nil, "OVERLAY")
                nameText:SetFont(valueFont, 11, "")
                nameText:SetPoint("TOPLEFT", btn, "TOPLEFT", 4, -5)
                nameText:SetWidth(TEXTURE_BUTTON_WIDTH - 8)
                nameText:SetJustifyH("LEFT")
                nameText:SetWordWrap(false)
                btn._nameText = nameText

                -- Texture preview (positioned at bottom with clear gap from name)
                local preview = btn:CreateTexture(nil, "ARTWORK", nil, 1)
                preview:SetSize(PREVIEW_WIDTH, PREVIEW_HEIGHT)
                preview:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 4, 5)
                btn._preview = preview

                self.TextureButtons[i] = btn
            end

            -- Position in grid (3 columns)
            local col = (i - 1) % TEXTURES_PER_ROW
            local row = math.floor((i - 1) / TEXTURES_PER_ROW)
            local x = col * (TEXTURE_BUTTON_WIDTH + TEXTURE_BUTTON_SPACING)
            local y = -(row * (TEXTURE_BUTTON_HEIGHT + TEXTURE_BUTTON_SPACING))
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)

            -- Set display name (strip "Blizzard " prefix on Blizzard tab)
            local stripPrefix = (selectedTab == "blizzard")
            local displayName = GetTextureDisplayName(textureKey, stripPrefix)
            btn._nameText:SetText(displayName)

            -- Set texture preview
            local texturePath = GetTexturePath(textureKey)
            if texturePath then
                btn._preview:SetTexture(texturePath)
                btn._preview:Show()
            else
                -- Default has no preview
                btn._preview:Hide()
            end

            -- Store data
            btn._textureKey = textureKey
            btn._accentR = self._accentR
            btn._accentG = self._accentG
            btn._accentB = self._accentB

            -- Selection state
            local isSelected = (currentValue == textureKey)
            btn._isSelected = isSelected
            if isSelected then
                btn._bg:SetColorTexture(self._accentR, self._accentG, self._accentB, 0.25)
                btn._nameText:SetTextColor(self._accentR, self._accentG, self._accentB, 1)
            else
                btn._bg:SetColorTexture(0, 0, 0, 0)
                btn._nameText:SetTextColor(1, 1, 1, 0.9)
            end

            -- Hover effects
            btn:SetScript("OnEnter", function(self)
                if not self._isSelected then
                    self._bg:SetColorTexture(self._accentR, self._accentG, self._accentB, 0.12)
                    self._nameText:SetTextColor(self._accentR, self._accentG, self._accentB, 1)
                else
                    self._bg:SetColorTexture(self._accentR, self._accentG, self._accentB, 0.30)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                if self._isSelected then
                    self._bg:SetColorTexture(self._accentR, self._accentG, self._accentB, 0.25)
                    self._nameText:SetTextColor(self._accentR, self._accentG, self._accentB, 1)
                else
                    self._bg:SetColorTexture(0, 0, 0, 0)
                    self._nameText:SetTextColor(1, 1, 1, 0.9)
                end
            end)

            -- Click to select
            btn:SetScript("OnClick", function(self)
                local key = self._textureKey
                if pickerSetting and pickerSetting.SetValue then
                    pickerSetting:SetValue(key)
                end
                if pickerCallback then
                    pickerCallback(key)
                end
                CloseBarTexturePicker()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end)

            btn:Show()
        end
    end

    -- Escape key to close
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            CloseBarTexturePicker()
        end
    end)

    -- Click outside to close
    frame:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", function(self, elapsed)
            if not self:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                C_Timer.After(0.05, function()
                    if pickerFrame and pickerFrame:IsShown() and not pickerFrame:IsMouseOver() then
                        CloseBarTexturePicker()
                    end
                end)
            end
        end)
    end)
    frame:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    pickerFrame = frame
    return frame
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function addon.ShowBarTexturePicker(anchor, setting, optionsProvider, callback)
    local frame = CreateBarTexturePicker()

    pickerSetting = setting
    pickerCallback = callback
    pickerAnchor = anchor

    -- Get current value and determine which tab to show
    local currentValue = nil
    if setting and setting.GetValue then
        currentValue = setting:GetValue()
    end

    -- Switch to appropriate tab if current texture is in a different category
    if currentValue then
        selectedTab = GetCategoryForTexture(currentValue)
    else
        selectedTab = "standard"
    end

    -- Update visuals and populate
    frame:UpdateTabVisuals()
    frame:PopulateContent()

    -- Position relative to anchor
    frame:ClearAllPoints()
    if anchor then
        local anchorBottom = anchor:GetBottom() or 0
        local frameHeight = frame:GetHeight()
        local screenHeight = GetScreenHeight() * UIParent:GetEffectiveScale()

        if anchorBottom - frameHeight < 50 then
            -- Not enough room below, show above
            frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
        else
            -- Show below
            frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        end
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    frame:Show()
    frame:Raise()
end

function addon.CloseBarTexturePicker()
    CloseBarTexturePicker()
end

--------------------------------------------------------------------------------
-- BarTextureSelector Row Control (for SettingsBuilder integration)
--------------------------------------------------------------------------------
-- Creates a selector row that opens the bar texture picker popup
-- Shows only the texture NAME (no inline preview)

local BAR_TEXTURE_SELECTOR_HEIGHT = 28
local BAR_TEXTURE_SELECTOR_ROW_HEIGHT = 42
local BAR_TEXTURE_SELECTOR_ROW_HEIGHT_WITH_DESC = 60
local BAR_TEXTURE_SELECTOR_WIDTH = 200
local BAR_TEXTURE_SELECTOR_PADDING = 12
local BAR_TEXTURE_SELECTOR_BORDER_ALPHA = 0.6

function Controls:CreateBarTextureSelector(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local label = options.label or "Bar Texture"
    local description = options.description
    local getValue = options.get or function() return "default" end
    local setValue = options.set or function() end
    local selectorWidth = options.width or BAR_TEXTURE_SELECTOR_WIDTH
    local selectorHeight = options.selectorHeight or BAR_TEXTURE_SELECTOR_HEIGHT
    local labelFontSize = options.labelFontSize or 13
    local name = options.name

    local hasDesc = description and description ~= ""
    local defaultRowHeight = hasDesc and BAR_TEXTURE_SELECTOR_ROW_HEIGHT_WITH_DESC or BAR_TEXTURE_SELECTOR_ROW_HEIGHT
    local rowHeight = options.rowHeight or defaultRowHeight

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if options.useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()

    -- Create the row frame
    local row = CreateFrame("Frame", name, parent)
    row:SetHeight(rowHeight)

    -- Row hover background
    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.08)
    hoverBg:Hide()
    row._hoverBg = hoverBg

    -- Row border (subtle line below)
    local rowBorder = row:CreateTexture(nil, "BORDER", nil, -1)
    rowBorder:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    rowBorder:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    rowBorder:SetHeight(1)
    rowBorder:SetColorTexture(ar, ag, ab, 0.2)
    row._rowBorder = rowBorder

    -- Label text (left side)
    local labelFS = row:CreateFontString(nil, "OVERLAY")
    local labelFont = theme:GetFont("LABEL")
    labelFS:SetFont(labelFont, labelFontSize, "")
    labelFS:SetPoint("LEFT", row, "LEFT", BAR_TEXTURE_SELECTOR_PADDING, hasDesc and 6 or 0)
    labelFS:SetText(label)
    labelFS:SetTextColor(ar, ag, ab, 1)
    row._label = labelFS

    -- Description text (below label, if provided)
    if hasDesc then
        local descFS = row:CreateFontString(nil, "OVERLAY")
        local descFont = theme:GetFont("VALUE")
        descFS:SetFont(descFont, 11, "")
        descFS:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -2)
        descFS:SetPoint("RIGHT", row, "RIGHT", -(selectorWidth + BAR_TEXTURE_SELECTOR_PADDING * 2), 0)
        descFS:SetText(description)
        descFS:SetTextColor(dimR, dimG, dimB, 1)
        descFS:SetJustifyH("LEFT")
        descFS:SetWordWrap(true)
        row._description = descFS
    end

    -- Selector button (right side, clickable to open popup)
    local selector = CreateFrame("Button", nil, row)
    selector:SetSize(selectorWidth, selectorHeight)
    selector:SetPoint("RIGHT", row, "RIGHT", -BAR_TEXTURE_SELECTOR_PADDING, 0)
    selector:EnableMouse(true)
    selector:RegisterForClicks("AnyUp")

    -- Selector border
    local selBorder = {}

    local selTop = selector:CreateTexture(nil, "BORDER", nil, -1)
    selTop:SetPoint("TOPLEFT", selector, "TOPLEFT", 0, 0)
    selTop:SetPoint("TOPRIGHT", selector, "TOPRIGHT", 0, 0)
    selTop:SetHeight(1)
    selTop:SetColorTexture(ar, ag, ab, BAR_TEXTURE_SELECTOR_BORDER_ALPHA)
    selBorder.TOP = selTop

    local selBottom = selector:CreateTexture(nil, "BORDER", nil, -1)
    selBottom:SetPoint("BOTTOMLEFT", selector, "BOTTOMLEFT", 0, 0)
    selBottom:SetPoint("BOTTOMRIGHT", selector, "BOTTOMRIGHT", 0, 0)
    selBottom:SetHeight(1)
    selBottom:SetColorTexture(ar, ag, ab, BAR_TEXTURE_SELECTOR_BORDER_ALPHA)
    selBorder.BOTTOM = selBottom

    local selLeft = selector:CreateTexture(nil, "BORDER", nil, -1)
    selLeft:SetPoint("TOPLEFT", selector, "TOPLEFT", 0, -1)
    selLeft:SetPoint("BOTTOMLEFT", selector, "BOTTOMLEFT", 0, 1)
    selLeft:SetWidth(1)
    selLeft:SetColorTexture(ar, ag, ab, BAR_TEXTURE_SELECTOR_BORDER_ALPHA)
    selBorder.LEFT = selLeft

    local selRight = selector:CreateTexture(nil, "BORDER", nil, -1)
    selRight:SetPoint("TOPRIGHT", selector, "TOPRIGHT", 0, -1)
    selRight:SetPoint("BOTTOMRIGHT", selector, "BOTTOMRIGHT", 0, 1)
    selRight:SetWidth(1)
    selRight:SetColorTexture(ar, ag, ab, BAR_TEXTURE_SELECTOR_BORDER_ALPHA)
    selBorder.RIGHT = selRight

    selector._border = selBorder

    -- Selector background
    local selBg = selector:CreateTexture(nil, "BACKGROUND", nil, -7)
    selBg:SetPoint("TOPLEFT", 1, -1)
    selBg:SetPoint("BOTTOMRIGHT", -1, 1)
    selBg:SetColorTexture(bgR, bgG, bgB, bgA)
    selector._bg = selBg

    -- Value text (shows texture NAME only, no inline preview)
    local valueText = selector:CreateFontString(nil, "OVERLAY")
    local valueFont = theme:GetFont("VALUE")
    valueText:SetFont(valueFont, 12, "")
    valueText:SetPoint("LEFT", selector, "LEFT", 8, 0)
    valueText:SetPoint("RIGHT", selector, "RIGHT", -24, 0)
    valueText:SetJustifyH("LEFT")
    valueText:SetWordWrap(false)
    valueText:SetTextColor(1, 1, 1, 1)
    selector._text = valueText

    -- Dropdown indicator arrow
    local arrowText = selector:CreateFontString(nil, "OVERLAY")
    local arrowFont = theme:GetFont("BUTTON")
    arrowText:SetFont(arrowFont, 10, "")
    arrowText:SetPoint("RIGHT", selector, "RIGHT", -6, 0)
    arrowText:SetText("▼")
    arrowText:SetTextColor(ar, ag, ab, 0.8)
    selector._arrow = arrowText

    row._selector = selector

    -- State tracking
    row._currentValue = getValue() or "default"
    row._getValue = getValue
    row._setValue = setValue

    -- Update display (NAME only, no texture preview)
    local function UpdateDisplay()
        local currentValue = row._currentValue
        local displayText = GetTextureDisplayName(currentValue)
        valueText:SetText(displayText)
    end

    -- Initial display update
    UpdateDisplay()

    -- Hover effects
    selector:SetScript("OnEnter", function(self)
        local r, g, b = theme:GetAccentColor()
        self._bg:SetColorTexture(r, g, b, 0.1)
        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, 0.8)
        end
        row._hoverBg:Show()
    end)

    selector:SetScript("OnLeave", function(self)
        local bgRc, bgGc, bgBc, bgAc = theme:GetBackgroundSolidColor()
        self._bg:SetColorTexture(bgRc, bgGc, bgBc, bgAc)
        local r, g, b = theme:GetAccentColor()
        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, BAR_TEXTURE_SELECTOR_BORDER_ALPHA)
        end
        row._hoverBg:Hide()
    end)

    -- Click to open bar texture picker popup
    selector:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)

        -- Create a pseudo-setting object for the picker
        local pseudoSetting = {
            GetValue = function()
                return row._currentValue
            end,
            SetValue = function(_, value)
                row._currentValue = value
                row._setValue(value)
                UpdateDisplay()
            end
        }

        -- Show the bar texture picker anchored to this selector
        addon.ShowBarTexturePicker(self, pseudoSetting, nil, function(selectedValue)
            row._currentValue = selectedValue
            row._setValue(selectedValue)
            UpdateDisplay()
        end)
    end)

    -- Row hover effects
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)
    row:SetScript("OnLeave", function(self)
        if not selector:IsMouseOver() then
            self._hoverBg:Hide()
        end
    end)

    -- Theme subscription
    local subscribeKey = "BarTextureSelector_" .. tostring(row)
    theme:Subscribe(subscribeKey, function(r, g, b)
        labelFS:SetTextColor(r, g, b, 1)
        rowBorder:SetColorTexture(r, g, b, 0.2)
        hoverBg:SetColorTexture(r, g, b, 0.08)
        arrowText:SetTextColor(r, g, b, 0.8)
        for _, tex in pairs(selBorder) do
            tex:SetColorTexture(r, g, b, BAR_TEXTURE_SELECTOR_BORDER_ALPHA)
        end
    end)
    row._subscribeKey = subscribeKey

    -- Public methods
    function row:GetValue()
        return self._currentValue
    end

    function row:SetValue(value)
        self._currentValue = value
        self._setValue(value)
        UpdateDisplay()
    end

    function row:Refresh()
        self._currentValue = self._getValue() or "default"
        UpdateDisplay()
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    return row
end
