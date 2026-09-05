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

local PICKER_HEIGHT = 420
local TAB_WIDTH = 90
local PADDING = 12

-- 3-column grid layout
local TEXTURES_PER_ROW = 3
local TEXTURE_BUTTON_WIDTH = 160
local TEXTURE_BUTTON_HEIGHT = 46  -- Height for name + preview with clear gap
local TEXTURE_BUTTON_SPACING = 6  -- Vertical spacing between items
local PREVIEW_WIDTH = 100
local PREVIEW_HEIGHT = 16

-- Fallback brand colors

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
    if addon.IsLSMKey and addon.IsLSMKey(key) then
        return addon.LSMKeyToName(key)
    end
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
    if addon.IsLSMKey and addon.IsLSMKey(textureKey) then return "shared" end
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

    -- Calculate content area width
    local contentWidth = (TEXTURE_BUTTON_WIDTH * TEXTURES_PER_ROW) + (TEXTURE_BUTTON_SPACING * (TEXTURES_PER_ROW - 1)) + (PADDING * 2)
    local totalWidth = TAB_WIDTH + contentWidth + 24 -- Extra for scrollbar

    local frame = Controls.CreatePickerShell({
        name = "ScootBarTexturePickerFrame",
        width = totalWidth,
        height = PICKER_HEIGHT,
        contentWidth = contentWidth,
        title = "Select Bar Texture",
        onClose = CloseBarTexturePicker,
        tabs = TABS,
        getSelectedTab = function() return selectedTab end,
        onTabSelected = function(key) selectedTab = key end,
    })

    -- Button pool for texture options
    frame.TextureButtons = {}

    -- Populate content function
    function frame:PopulateContent()
        local currentTab = nil
        for _, tabData in ipairs(self._workingTabs or TABS) do
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

    -- Build working tabs (static tabs + optional LSM "Shared" tab)
    local workingTabs = {}
    for i, tabData in ipairs(TABS) do
        workingTabs[i] = tabData
    end
    if addon.LSMAvailable then
        -- Build dedup set from Scoot-internal texture paths
        local internalPaths = {}
        for _, texKey in ipairs(STANDARD_TEXTURES) do
            local path = addon.Media.ResolveBarTexturePath(texKey)
            if path then internalPaths[path:lower()] = true end
        end
        for _, texKey in ipairs(BLIZZARD_TEXTURES) do
            local path = addon.Media.ResolveBarTexturePath(texKey)
            if path then internalPaths[path:lower()] = true end
        end
        -- Filter LSM entries
        local filteredKeys = {}
        local lsmNames = addon.LSM:List("statusbar")
        for _, lsmName in ipairs(lsmNames) do
            local path = addon.LSM:Fetch("statusbar", lsmName, true)
            if path and not internalPaths[path:lower()] then
                filteredKeys[#filteredKeys + 1] = addon.LSMNameToKey(lsmName)
            end
        end
        if #filteredKeys > 0 then
            workingTabs[#workingTabs + 1] = { key = "shared", label = "Shared", textures = filteredKeys }
        end
    end
    frame._workingTabs = workingTabs

    -- Switch to appropriate tab if current texture is in a different category
    if currentValue then
        selectedTab = GetCategoryForTexture(currentValue)
    else
        selectedTab = "standard"
    end
    -- Fallback if selected category (e.g. "shared") has no tab
    local tabFound = false
    for _, tabData in ipairs(workingTabs) do
        if tabData.key == selectedTab then tabFound = true; break end
    end
    if not tabFound then selectedTab = "standard" end

    -- Update tabs, visuals and populate
    frame:UpdateTabs()
    frame:UpdateTabVisuals()
    frame:PopulateContent()

    -- Position relative to anchor
    frame:ClearAllPoints()
    if anchor then
        local anchorBottom = anchor:GetBottom() or 0
        local frameHeight = frame:GetHeight()

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

    -- Create the row frame
    local row = CreateFrame("Frame", name, parent)
    row:SetHeight(rowHeight)

    -- Row hover background
    row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })

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

    -- Selector border (brightens on hover)
    selector._border = Controls.CreateBorder(selector, {
        alpha = BAR_TEXTURE_SELECTOR_BORDER_ALPHA,
        getAlpha = function(self) return self:IsMouseOver() and 0.8 or BAR_TEXTURE_SELECTOR_BORDER_ALPHA end,
    })

    -- Selector background
    selector._bg = Controls.AddBackground(selector, { inset = 1, sublevel = Controls.SUBLEVEL_FILL })

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
        if addon.IsLSMKey and addon.IsLSMKey(currentValue) and not addon.LSMAvailable then
            displayText = displayText .. " (missing)"
        end
        valueText:SetText(displayText)
    end

    -- Initial display update
    UpdateDisplay()

    -- Hover effects
    selector:SetScript("OnEnter", function(self)
        local r, g, b = theme:GetAccentColor()
        self._bg:SetColorTexture(r, g, b, 0.1)
        self._border:Refresh()
        row._hoverBg:Show()
    end)

    selector:SetScript("OnLeave", function(self)
        local bgRc, bgGc, bgBc, bgAc = theme:GetBackgroundSolidColor()
        self._bg:SetColorTexture(bgRc, bgGc, bgBc, bgAc)
        self._border:Refresh()
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
        arrowText:SetTextColor(r, g, b, 0.8)
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
