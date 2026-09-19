-- FontPicker.lua - Tabbed font picker dialog on the shared picker shell
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
-- State and layout
--------------------------------------------------------------------------------

local fontPickerFrame = nil
local fontPickerSetting = nil
local fontPickerCallback = nil
local selectedFontTab = "default"

-- Grid layout constants
local FONTS_PER_ROW = 3
local FONT_BUTTON_WIDTH = 160
local FONT_BUTTON_HEIGHT = 26
local FONT_BUTTON_SPACING = 4
local PICKER_PADDING = 12
local PICKER_HEIGHT = 420
local TAB_WIDTH = 90

-- Token band (the two global-font buttons under the title). Each carries two
-- lines, the token's name over the face it currently points at, so the height
-- is the pair plus the art's own padding.
local TOKEN_BUTTON_WIDTH = 230
local TOKEN_BUTTON_HEIGHT = 40
local TITLE_INSET_PLAIN = 30
local TITLE_INSET_BAND = TITLE_INSET_PLAIN + TOKEN_BUTTON_HEIGHT + 10

--------------------------------------------------------------------------------
-- Font Category Tables
--------------------------------------------------------------------------------

-- GAME_DEFAULT has no entry: it draws the same face as FRIZQT__, whose entry
-- lights for a field still holding it.
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

-- What a global font token points at right now: the display name of the key
-- addon.NormalizeFontKey resolves it to. A host whose Apply All page has
-- never written one resolves to FRIZQT__, so the band reads "Friz Quadrata
-- (Default)" rather than saying nothing.
local function TokenValueName(token)
    local key = addon.NormalizeFontKey and addon.NormalizeFontKey(token) or "FRIZQT__"
    if addon.IsLSMKey and addon.IsLSMKey(key) then
        return addon.LSMKeyToName(key)
    end
    return (addon.FontDisplayNames and addon.FontDisplayNames[key]) or key
end

-- The band button's top line: what clicking it does. The token's own name
-- sits inside it, so the line reads as the action and the face name below it
-- reads as the value that action follows.
local function TokenActionLabel(token)
    if token == addon.MediaTokens.BODY_FONT then
        return "Use the Global Body font"
    end
    return "Use the Global Header font"
end

local function CloseFontPicker()
    if fontPickerFrame then
        fontPickerFrame:Hide()
    end
    fontPickerSetting = nil
    fontPickerCallback = nil
end

local function CreateFontPicker()
    if fontPickerFrame then return fontPickerFrame end

    -- The grid's own width. The shell adds the tab column and the rest of
    -- the chrome around it to size the dialog.
    local contentWidth = (FONT_BUTTON_WIDTH * FONTS_PER_ROW) + (FONT_BUTTON_SPACING * (FONTS_PER_ROW - 1))

    local frame = Controls.CreatePickerShell({
        -- Brand-named, and still ending in "Frame": CreatePickerShell derives
        -- the scroll frame and scrollbar names from that suffix.
        name = (addon.Brand or "Scoot") .. "FontPickerFrame",
        height = PICKER_HEIGHT,
        contentWidth = contentWidth,
        tabWidth = TAB_WIDTH,
        title = "Select Font",
        onClose = CloseFontPicker,
        tabs = FONT_TABS,
        getSelectedTab = function() return selectedFontTab end,
        onTabSelected = function(key) selectedFontTab = key end,
    })

    -- Button pool for font options
    frame.Buttons = {}

    -- Token band: two buttons under the title that write the global font
    -- tokens (global:header / global:body) into the field. Hidden when the
    -- caller passes suppressTokens (the Apply All and SCT pickers). Each
    -- button carries the action on the top line and, under it in parentheses,
    -- the face that token points at right now, drawn small and dim in that
    -- face, so the band says what choosing it will draw with.
    local band = CreateFrame("Frame", nil, frame)
    local bandInset = frame._padInset or PICKER_PADDING
    band:SetPoint("TOPLEFT", frame, "TOPLEFT", bandInset, -(TITLE_INSET_PLAIN + 2))
    band:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -bandInset, -(TITLE_INSET_PLAIN + 2))
    band:SetHeight(TOKEN_BUTTON_HEIGHT)
    band:Hide()
    band.Buttons = {}
    frame.TokenBand = band

    -- The button role's art where the skin has some, the framework's fill and
    -- border where it does not. Controls:CreateButton carries one label and
    -- these carry two, so the draw is here rather than through it.
    local buttonKind = addon.UI.Chrome.Spec("button").kind
    local bandArt = buttonKind ~= "flat" and buttonKind ~= "template"

    local bandTokens = { addon.MediaTokens.HEADER_FONT, addon.MediaTokens.BODY_FONT }
    for i, token in ipairs(bandTokens) do
        local btn = CreateFrame("Button", nil, band)
        btn:SetSize(TOKEN_BUTTON_WIDTH, TOKEN_BUTTON_HEIGHT)
        btn:EnableMouse(true)
        btn:RegisterForClicks("AnyUp")
        if i == 1 then
            btn:SetPoint("RIGHT", band, "CENTER", -4, 0)
        else
            btn:SetPoint("LEFT", band, "CENTER", 4, 0)
        end

        -- The action, in the panel's label font. Both lines span the button's
        -- width from a corner pair rather than LEFT plus TOP, which would give
        -- the string two vertical anchors.
        local caption = btn:CreateFontString(nil, "OVERLAY")
        GetTheme():ApplyFont(caption, "label", 12)
        caption:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -6)
        caption:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, -6)
        caption:SetJustifyH("CENTER")
        caption:SetWordWrap(false)
        caption:SetText(TokenActionLabel(token))
        btn.Caption = caption

        -- The face it points at, in parentheses and drawn in that face
        local value = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        value:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -2)
        value:SetPoint("TOPRIGHT", caption, "BOTTOMRIGHT", 0, -2)
        value:SetJustifyH("CENTER")
        value:SetWordWrap(false)
        btn.Value = value

        if bandArt then
            btn._backdrop = addon.UI.Chrome.Backdrop("button", btn, { label = caption })
        else
            local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0)
            btn._bg = bg
            btn._borders = Controls.CreateBorder(btn, { alpha = 0.5 })
        end

        btn._fontValue = token

        -- One repaint for both draws: the art follows the state flags, the
        -- flat fill and the two label colors are set here.
        function btn:Paint()
            local dr, dg, db = GetTheme():GetDimTextColor()
            if self._backdrop then
                self._backdrop:SetHover(self._isHover)
                self._backdrop:SetSelected(self._isSelected)
                self.Value:SetTextColor(dr, dg, db, 1)
                return
            end
            local ar, ag, ab = self._accentR or 1, self._accentG or 1, self._accentB or 1
            local lit = self._isSelected or self._isHover
            local alpha = (self._isSelected and self._isHover and 0.30)
                or (self._isSelected and 0.25) or (self._isHover and 0.12) or 0
            self._bg:SetColorTexture(ar, ag, ab, alpha)
            if lit then
                self.Caption:SetTextColor(ar, ag, ab, 1)
            else
                self.Caption:SetTextColor(1, 1, 1, 0.9)
            end
            self.Value:SetTextColor(dr, dg, db, 1)
        end

        btn:SetScript("OnClick", function(self)
            local picked = self._fontValue
            if fontPickerSetting and fontPickerSetting.SetValue then
                fontPickerSetting:SetValue(picked)
            end
            if fontPickerCallback then
                fontPickerCallback(picked)
            end
            CloseFontPicker()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)
        btn:SetScript("OnEnter", function(self)
            self._isHover = true
            self:Paint()
        end)
        btn:SetScript("OnLeave", function(self)
            self._isHover = false
            self:Paint()
        end)

        band.Buttons[i] = btn
    end

    -- The help icon left of the pair, carrying the same line the selector
    -- field shows while it holds one of these tokens (FontSelector.lua).
    local bandInfo = Controls:CreateInfoIcon({
        parent = band,
        tooltipText = "The Global Fonts are set on the Apply All > Font menu.",
        size = 14,
    })
    if bandInfo then
        bandInfo:SetPoint("RIGHT", band.Buttons[1], "LEFT", -8, 0)
        band.InfoIcon = bandInfo
    end

    -- Repaint the band: the parenthesized line in the token's resolved face
    -- and its current name, selection highlight when the field already holds
    -- that token. Runs from PopulateContent so accent changes retint it too.
    function frame:UpdateTokenBand()
        if not self.TokenBand:IsShown() then return end
        local currentValue = nil
        if fontPickerSetting and fontPickerSetting.GetValue then
            currentValue = fontPickerSetting:GetValue()
        end
        local defaultFont = select(1, _G.GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF"
        for _, btn in ipairs(self.TokenBand.Buttons) do
            local token = btn._fontValue
            local face = addon.ResolveFontFace(token)
            if not (face and pcall(btn.Value.SetFont, btn.Value, face, 10, "")) then
                pcall(btn.Value.SetFont, btn.Value, defaultFont, 10, "")
            end
            btn.Value:SetText(("(%s)"):format(TokenValueName(token)))
            btn._accentR = self._accentR
            btn._accentG = self._accentG
            btn._accentB = self._accentB
            btn._isSelected = (currentValue == token)
            btn:Paint()
        end
    end

    -- Populate content for selected tab
    function frame:PopulateContent()
        self:UpdateTokenBand()
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
        if currentValue == "GAME_DEFAULT" then currentValue = "FRIZQT__" end

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
                label:SetPoint("LEFT", btn, "LEFT", 8, 0)
                label:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
                label:SetJustifyH("LEFT")
                label:SetWordWrap(false)
                btn.Label = label

                -- The grid is a list of choices, so each cell takes the
                -- navRow role: the skin's row art under the cursor and under
                -- the font the field already holds, and the name colored by
                -- the same state walk. The name's own face is set below and
                -- the role never touches it.
                btn._backdrop = addon.UI.Chrome.Backdrop("navRow", btn, {
                    variant = "child", label = label,
                })

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
            btn._backdrop:SetSelected(isSelected)

            -- Click handler
            btn:SetScript("OnClick", function(self)
                local value = self._fontValue
                if fontPickerSetting and fontPickerSetting.SetValue then
                    fontPickerSetting:SetValue(value)
                end
                if fontPickerCallback then
                    fontPickerCallback(value)
                end
                CloseFontPicker()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end)

            -- Hover effects
            btn:SetScript("OnEnter", function(self)
                self._backdrop:SetHover(true)
            end)
            btn:SetScript("OnLeave", function(self)
                self._backdrop:SetHover(false)
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

-- opts (optional table): suppressTokens hides the global-token band; the
-- Apply All pickers (which SET the globals) and SCT (game restart) pass it.
function addon.ShowFontPicker(anchor, setting, opts, callback)
    local frame = CreateFontPicker()

    fontPickerSetting = setting
    fontPickerCallback = callback

    local suppressTokens = type(opts) == "table" and opts.suppressTokens == true
    frame.TokenBand:SetShown(not suppressTokens)
    frame:SetTitleInset(suppressTokens and TITLE_INSET_PLAIN or TITLE_INSET_BAND)

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
