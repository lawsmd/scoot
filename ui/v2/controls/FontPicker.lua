-- FontPicker.lua - Tabbed font picker dialog on the shared picker shell
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

--------------------------------------------------------------------------------
-- State and layout
--------------------------------------------------------------------------------

local fontPickerFrame = nil
local fontPickerSetting = nil
local fontPickerCallback = nil
local fontPickerAnchor = nil
local selectedFontTab = "default"

-- Grid layout constants
local FONTS_PER_ROW = 3
local FONT_BUTTON_WIDTH = 160
local FONT_BUTTON_HEIGHT = 26
local FONT_BUTTON_SPACING = 4
local PICKER_PADDING = 12
local PICKER_HEIGHT = 420
local TAB_WIDTH = 90

--------------------------------------------------------------------------------
-- Font Category Tables
--------------------------------------------------------------------------------

local DEFAULT_FONTS = { "FRIZQT__", "ARIALN", "MORPHEUS", "SKURRI" }

local GOOGLE_FONTS = {
    -- Dosis
    "DOSIS_REG", "DOSIS_BOLD", "DOSIS_LIGHT", "DOSIS_MED",
    -- Exo 2
    "EXO2_REG", "EXO2_BLACK", "EXO2_BOLD", "EXO2_LIGHT", "EXO2_MED",
    -- Fira Sans
    "FIRASANS_REG", "FIRASANS_BLACK", "FIRASANS_BOLD", "FIRASANS_LIGHT", "FIRASANS_MED",
    -- Lato
    "LATO_REG", "LATO_BLACK", "LATO_BOLD", "LATO_LIGHT",
    -- Montserrat
    "MONTSERRAT_REG", "MONTSERRAT_BLACK", "MONTSERRAT_BOLD", "MONTSERRAT_LIGHT", "MONTSERRAT_MED",
    -- Mukta
    "MUKTA_REG", "MUKTA_BOLD", "MUKTA_LIGHT", "MUKTA_MED",
    -- Poppins
    "POPPINS_REG", "POPPINS_BLACK", "POPPINS_BOLD", "POPPINS_LIGHT", "POPPINS_MED",
    -- Roboto
    "ROBOTO_REG", "ROBOTO_BLACK", "ROBOTO_LIGHT", "ROBOTO_MED",
    -- Roboto Condensed
    "ROBOTO_COND_REG", "ROBOTO_COND_BLACK", "ROBOTO_COND_BOLD", "ROBOTO_COND_LIGHT", "ROBOTO_COND_MED",
    -- Roboto SemiCondensed
    "ROBOTO_SEMICOND_REG", "ROBOTO_SEMICOND_BLACK", "ROBOTO_SEMICOND_BOLD", "ROBOTO_SEMICOND_LIGHT", "ROBOTO_SEMICOND_MED",
}

local PIXEL_FONTS = {
    "FONT_04B30",
    "DOGICA_REG", "DOGICA_BOLD", "DOGICA_PIXEL", "DOGICA_PIXELBOLD",
    "MINECRAFT",
    "PIXELOP_REG", "PIXELOP_BOLD", "PIXELOP_MONO", "PIXELOP_MONOBOLD",
    "PIXELOP_SC", "PIXELOP_SCBOLD",
    "PIXELLARI", "PRESS_START_2P", "RAINYHEARTS",
}

-- Heavy display faces (the font picker's "Display" tab).
local DISPLAY_FONTS = {
    "ANTON_WIDE_150", "RUBIK_MONO_ONE", "TOMORROW_BLACK", "BUNGEE",
}

local FONT_TABS = {
    { key = "default", label = "Default", fonts = DEFAULT_FONTS },
    { key = "google",  label = "Google",  fonts = GOOGLE_FONTS },
    { key = "pixel",   label = "Pixel",   fonts = PIXEL_FONTS },
    { key = "display", label = "Display", fonts = DISPLAY_FONTS },
}

-- Build a reverse lookup: font key -> tab key
local fontCategoryMap = {}
for _, tabData in ipairs(FONT_TABS) do
    for _, fontKey in ipairs(tabData.fonts) do
        fontCategoryMap[fontKey] = tabData.key
    end
end

local function GetCategoryForFont(key)
    if addon.IsLSMKey and addon.IsLSMKey(key) then return "shared" end
    return fontCategoryMap[key] or "default"
end

local function CloseFontPicker()
    if fontPickerFrame then
        fontPickerFrame:Hide()
    end
    fontPickerSetting = nil
    fontPickerCallback = nil
    fontPickerAnchor = nil
end

local function CreateFontPicker()
    if fontPickerFrame then return fontPickerFrame end

    -- Calculate content area width (right of tabs)
    local contentWidth = (FONT_BUTTON_WIDTH * FONTS_PER_ROW) + (FONT_BUTTON_SPACING * (FONTS_PER_ROW - 1)) + (PICKER_PADDING * 2)
    local totalWidth = TAB_WIDTH + contentWidth + 24 -- tabs + content + scrollbar

    local frame = Controls.CreatePickerShell({
        name = "ScootFontPickerFrame",
        width = totalWidth,
        height = PICKER_HEIGHT,
        contentWidth = contentWidth,
        title = "Select Font",
        onClose = CloseFontPicker,
        tabs = FONT_TABS,
        getSelectedTab = function() return selectedFontTab end,
        onTabSelected = function(key) selectedFontTab = key end,
    })

    -- Button pool for font options
    frame.Buttons = {}

    -- Populate content for selected tab
    function frame:PopulateContent()
        local currentTab = nil
        for _, tabData in ipairs(self._workingTabs or FONT_TABS) do
            if tabData.key == selectedFontTab then
                currentTab = tabData
                break
            end
        end
        if not currentTab then return end

        local fonts = currentTab.fonts
        local contentFrame = self.Content
        local displayNames = addon.FontDisplayNames or {}
        local defaultFont = select(1, _G.GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF"

        local accentR = self._accentR
        local accentG = self._accentG
        local accentB = self._accentB

        -- Get current value
        local currentValue = nil
        if fontPickerSetting and fontPickerSetting.GetValue then
            currentValue = fontPickerSetting:GetValue()
        end

        -- Calculate content height
        local numRows = math.ceil(#fonts / FONTS_PER_ROW)
        local contentHeight = (numRows * FONT_BUTTON_HEIGHT) + ((numRows - 1) * FONT_BUTTON_SPACING) + PICKER_PADDING
        contentFrame:SetHeight(contentHeight)

        -- Show/hide scrollbar based on content size
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

        -- Hide all existing buttons
        for _, btn in ipairs(self.Buttons) do
            btn:Hide()
        end

        -- Create/reuse buttons for each font
        for i, fontKey in ipairs(fonts) do
            local btn = self.Buttons[i]
            if not btn then
                btn = CreateFrame("Button", nil, contentFrame)
                btn:SetSize(FONT_BUTTON_WIDTH, FONT_BUTTON_HEIGHT)
                btn:EnableMouse(true)
                btn:RegisterForClicks("AnyUp")

                local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("LEFT", btn, "LEFT", 4, 0)
                label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                label:SetJustifyH("LEFT")
                label:SetWordWrap(false)
                btn.Label = label

                self.Buttons[i] = btn
            end

            -- Position in grid
            local col = (i - 1) % FONTS_PER_ROW
            local row = math.floor((i - 1) / FONTS_PER_ROW)
            local x = col * (FONT_BUTTON_WIDTH + FONT_BUTTON_SPACING)
            local y = -(row * (FONT_BUTTON_HEIGHT + FONT_BUTTON_SPACING))
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", x, y)

            -- Set font preview (render label in that font)
            local fontFace = addon.ResolveFontFace(fontKey)
            local fontSet = false
            if fontFace then
                fontSet = pcall(btn.Label.SetFont, btn.Label, fontFace, 12, "")
            end
            if not fontSet then
                pcall(btn.Label.SetFont, btn.Label, defaultFont, 12, "")
            end

            -- Set display name
            local displayText
            if addon.IsLSMKey and addon.IsLSMKey(fontKey) then
                displayText = addon.LSMKeyToName(fontKey)
            else
                displayText = displayNames[fontKey] or fontKey
            end
            btn.Label:SetText(displayText)

            -- Selection state
            local isSelected = (currentValue == fontKey)
            btn._fontValue = fontKey
            btn._isSelected = isSelected
            btn._accentR = accentR
            btn._accentG = accentG
            btn._accentB = accentB

            if isSelected then
                btn.Label:SetTextColor(accentR, accentG, accentB, 1)
            else
                btn.Label:SetTextColor(1, 1, 1, 0.9)
            end

            -- Click handler
            btn:SetScript("OnClick", function(self)
                local value = self._fontValue
                if fontPickerSetting and fontPickerSetting.SetValue then
                    fontPickerSetting:SetValue(value)
                end
                if fontPickerCallback then
                    fontPickerCallback(value)
                end
                if fontPickerAnchor and fontPickerAnchor.Text then
                    local dt
                    if addon.IsLSMKey and addon.IsLSMKey(value) then
                        dt = addon.LSMKeyToName(value)
                    else
                        dt = addon.FontDisplayNames and addon.FontDisplayNames[value] or value
                    end
                    fontPickerAnchor.Text:SetText(dt)
                end
                CloseFontPicker()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end)

            -- Hover effects
            btn:SetScript("OnEnter", function(self)
                if not self._isSelected then
                    self.Label:SetTextColor(self._accentR, self._accentG, self._accentB, 1)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                if self._isSelected then
                    self.Label:SetTextColor(self._accentR, self._accentG, self._accentB, 1)
                else
                    self.Label:SetTextColor(1, 1, 1, 0.9)
                end
            end)

            btn:Show()
        end
    end

    fontPickerFrame = frame
    return frame
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function addon.ShowFontPicker(anchor, setting, optionsProvider, callback)
    local frame = CreateFontPicker()

    fontPickerSetting = setting
    fontPickerCallback = callback
    fontPickerAnchor = anchor

    -- Get current value and determine which tab to show
    local currentValue = nil
    if setting and setting.GetValue then
        currentValue = setting:GetValue()
    end

    -- Build working tabs (static tabs + optional LSM "Shared" tab)
    local workingTabs = {}
    for i, tabData in ipairs(FONT_TABS) do
        workingTabs[i] = tabData
    end
    if addon.LSMAvailable then
        -- Build dedup set from Scoot-internal font paths
        local internalPaths = {}
        if addon.Fonts then
            for _, path in pairs(addon.Fonts) do
                internalPaths[path:lower()] = true
            end
        end
        -- Filter LSM entries
        local filteredKeys = {}
        local lsmNames = addon.LSM:List("font")
        for _, lsmName in ipairs(lsmNames) do
            local path = addon.LSM:Fetch("font", lsmName, true)
            if path and not internalPaths[path:lower()] then
                filteredKeys[#filteredKeys + 1] = addon.LSMNameToKey(lsmName)
            end
        end
        if #filteredKeys > 0 then
            workingTabs[#workingTabs + 1] = { key = "shared", label = "Shared", fonts = filteredKeys }
        end
    end
    frame._workingTabs = workingTabs

    -- Auto-select tab containing the currently selected font
    if currentValue then
        selectedFontTab = GetCategoryForFont(currentValue)
    else
        selectedFontTab = "default"
    end
    -- Fallback if selected category (e.g. "shared") has no tab
    local tabFound = false
    for _, tabData in ipairs(workingTabs) do
        if tabData.key == selectedFontTab then tabFound = true; break end
    end
    if not tabFound then selectedFontTab = "default" end

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
            frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
        else
            frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        end
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    frame:Show()
    frame:Raise()

    -- Preload fonts for smooth rendering
    if addon.PreloadFonts then
        addon.PreloadFonts()
    end
end

function addon.CloseFontPicker()
    CloseFontPicker()
end

function addon.CloseFontPicker()
    CloseFontPicker()
end
