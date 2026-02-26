local addonName, addon = ...

addon.Fonts = addon.Fonts or {}
addon.WorldTextFontLog = addon.WorldTextFontLog or {}

local function SnapshotFontObject(fontObj)
    if type(fontObj) ~= "table" or not fontObj.GetFont then
        return "<unavailable>"
    end
    local ok, path, size, flags = pcall(fontObj.GetFont, fontObj)
    if not ok then
        return "<error>"
    end
    return string.format("%s | size=%s | flags=%s", tostring(path or "?"), tostring(size or "?"), tostring(flags or ""))
end

local function FormatExtra(info)
    if type(info) ~= "table" then
        return tostring(info or "")
    end
    local parts = {}
    for k, v in pairs(info) do
        table.insert(parts, string.format("%s=%s", tostring(k), tostring(v)))
    end
    table.sort(parts)
    return table.concat(parts, "; ")
end

local function AppendWorldTextFontLog(stage, info)
    local log = addon.WorldTextFontLog
    if type(log) ~= "table" then
        log = {}
        addon.WorldTextFontLog = log
    end
    local timestamp = string.format("%.1fms", debugprofilestop())
    local snapshot = string.format("DAMAGE_TEXT_FONT=%s | CombatTextFont=%s | CombatTextFontOutline=%s",
        tostring(_G.DAMAGE_TEXT_FONT),
        SnapshotFontObject(_G.CombatTextFont),
        SnapshotFontObject(_G.CombatTextFontOutline)
    )
    local line = string.format("[%s] %s :: %s", timestamp, tostring(stage or "?"), snapshot)
    local extra = FormatExtra(info)
    if extra ~= "" then
        line = line .. " || " .. extra
    end
    table.insert(log, line)
    -- Limit log size
    if #log > 200 then
        table.remove(log, 1)
    end
end

addon.LogWorldTextFont = AppendWorldTextFontLog

function addon.ShowWorldTextFontLog()
    if addon.DebugShowWindow then
        addon.DebugShowWindow("World Text Font Log", addon.WorldTextFontLog)
    elseif addon.Print then
        addon:Print("Debug window unavailable; open after core/debug.lua loads.")
    end
end

AppendWorldTextFontLog("fonts.lua:load", { init = true })

-- Build a container compatible with Settings dropdown options for font faces.
-- This mirrors RIP's behavior but keeps Scoot self-contained. We rely on
-- stock fonts available in all clients and allow future extension via media.
function addon.BuildFontOptionsContainer()
    local create = _G.Settings and _G.Settings.CreateControlTextContainer
    local displayNames = addon.FontDisplayNames or {}

    local add = function(container, key, text)
        if container._seen and container._seen[key] then return end
        if create then
            container:Add(key, text)
        else
            table.insert(container, { value = key, text = text })
        end
        if container._seen then container._seen[key] = true end
    end

    local container = create and create() or {}
    container._seen = {}

    -- Always include FRIZQT__ first (stock default)
    add(container, "FRIZQT__", displayNames.FRIZQT__ or "FRIZQT__")

    -- Add stock fonts next (excluding FRIZQT__ which is already added)
    local stockFonts = { "ARIALN", "MORPHEUS", "SKURRI" }
    for _, k in ipairs(stockFonts) do
        add(container, k, displayNames[k] or k)
    end

    -- Collect and sort all registered fonts by their display names for alphabetical ordering
    local fontEntries = {}
    for k, _ in pairs(addon.Fonts or {}) do
        -- Skip stock fonts (already added above)
        if k ~= "FRIZQT__" and k ~= "ARIALN" and k ~= "MORPHEUS" and k ~= "SKURRI" then
            local display = displayNames[k] or k
            table.insert(fontEntries, { key = k, display = display })
        end
    end

    -- Sort by display name for cleaner grouping (Dosis, Exo 2, Lato, etc.)
    table.sort(fontEntries, function(a, b)
        return a.display < b.display
    end)

    -- Add all custom fonts
    for _, entry in ipairs(fontEntries) do
        add(container, entry.key, entry.display)
    end

    container._seen = nil
    return create and container:GetData() or container
end

-- Resolve a font face name to an actual file path for SetFont.
-- Falls back to the face of GameFontNormal if unknown.
function addon.ResolveFontFace(key)
    local face = (addon.Fonts and addon.Fonts[key or "FRIZQT__"]) or (select(1, _G.GameFontNormal:GetFont()))
    return face
end

--------------------------------------------------------------------------------
-- Font Style Application Helper (supports SHADOW and HEAVY prefixes)
--------------------------------------------------------------------------------
-- Apply font settings to a FontString with support for shadow-prefixed styles.
-- Supported styles: NONE, OUTLINE, THICKOUTLINE, plus these prefixes:
--   SHADOW*: adds a subtle drop shadow (offset 1, -1) for extra visual weight.
--   HEAVY*: adds a centered glow effect (offset 0, 0) - thickens without directional shadow.
function addon.ApplyFontStyle(fs, font, size, style)
    if not fs then return end
    style = style or ""

    -- Detect prefixes (check longer ones first to avoid partial matches)
    local heavy = false
    local shadow = false

    if style:sub(1, 11) == "HEAVYSHADOW" then
        -- Backward compat: HEAVYSHADOW* saved settings render as regular SHADOW
        shadow = true
        style = style:sub(12) -- Strip HEAVYSHADOW prefix
    elseif style:sub(1, 5) == "HEAVY" then
        heavy = true
        style = style:sub(6) -- Strip HEAVY prefix
    elseif style:sub(1, 6) == "SHADOW" then
        shadow = true
        style = style:sub(7) -- Strip SHADOW prefix
    end

    -- Normalize "NONE" to empty string (Blizzard convention)
    if style == "NONE" or style == "" then
        style = ""
    end

    -- Apply the font
    if fs.SetFont then
        pcall(fs.SetFont, fs, font, size, style)
    end

    -- Apply shadow settings
    if fs.SetShadowColor and fs.SetShadowOffset then
        if heavy then
            -- Heavy: thickens text with upper-right offset (opposite of drop shadow look)
            pcall(fs.SetShadowColor, fs, 0, 0, 0, 0.9)
            pcall(fs.SetShadowOffset, fs, 1, 1)
        elseif shadow then
            -- Regular shadow: dark color with subtle offset
            pcall(fs.SetShadowColor, fs, 0, 0, 0, 0.8)
            pcall(fs.SetShadowOffset, fs, 1, -1)
        else
            -- No shadow: transparent with no offset
            pcall(fs.SetShadowColor, fs, 0, 0, 0, 0)
            pcall(fs.SetShadowOffset, fs, 0, 0)
        end
    end
end

--------------------------------------------------------------------------------
-- Custom Font Picker Popup (3-Column Scrollable Grid)
--------------------------------------------------------------------------------

local fontPickerFrame = nil
local fontPickerSetting = nil
local fontPickerCallback = nil
local fontPickerAnchor = nil

-- Grid layout constants
local FONTS_PER_ROW = 3
local FONT_BUTTON_WIDTH = 160
local FONT_BUTTON_HEIGHT = 26
local FONT_BUTTON_SPACING = 4
local PICKER_PADDING = 12
local PICKER_TITLE_HEIGHT = 30

-- Scoot theme colors
local BRAND_R, BRAND_G, BRAND_B = 0.20, 0.90, 0.30

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

    -- Get UI theme colors if available, fallback to brand colors
    local Theme = addon.UI and addon.UI.Theme
    local accentR, accentG, accentB = BRAND_R, BRAND_G, BRAND_B
    if Theme and Theme.GetAccentColor then
        accentR, accentG, accentB = Theme:GetAccentColor()
    end

    -- Calculate popup dimensions based on grid
    local contentWidth = (FONT_BUTTON_WIDTH * FONTS_PER_ROW) + (FONT_BUTTON_SPACING * (FONTS_PER_ROW - 1)) + (PICKER_PADDING * 2)
    local popupWidth = contentWidth + 24 -- Extra for scrollbar
    local popupHeight = 420

    local frame = CreateFrame("Frame", "ScootFontPickerFrame", UIParent)
    frame:SetSize(popupWidth, popupHeight)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- TUI-style background (dark, semi-transparent)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.06, 0.96)
    frame._bg = bg

    -- TUI-style border (accent color)
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

    -- Title (TUI style - white text, JetBrains Mono if available)
    local title = frame:CreateFontString(nil, "OVERLAY")
    local titleFont = (Theme and Theme.GetFont and Theme:GetFont("HEADER")) or "Fonts\\FRIZQT__.TTF"
    title:SetFont(titleFont, 14, "")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PICKER_PADDING, -10)
    title:SetText("Select Font")
    title:SetTextColor(1, 1, 1, 1)
    frame.Title = title

    -- TUI-style close button (X)
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
    closeBtn:SetScript("OnClick", CloseFontPicker)
    frame.CloseButton = closeBtn

    -- Scroll frame for content (minimal template, we'll style the scrollbar)
    local scrollFrame = CreateFrame("ScrollFrame", "ScootFontPickerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PICKER_PADDING, -(PICKER_TITLE_HEIGHT + 4))
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(PICKER_PADDING + 20), PICKER_PADDING)
    frame.ScrollFrame = scrollFrame

    -- Style the scrollbar to match TUI
    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 16)

        -- Hide default textures and restyle
        if scrollBar.Background then scrollBar.Background:Hide() end
        if scrollBar.Track then
            if scrollBar.Track.Begin then scrollBar.Track.Begin:Hide() end
            if scrollBar.Track.End then scrollBar.Track.End:Hide() end
            if scrollBar.Track.Middle then scrollBar.Track.Middle:Hide() end
        end

        -- Create custom track background
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

        -- Hide up/down buttons or style them minimally
        local upBtn = scrollBar.ScrollUpButton or scrollBar.Back or _G[scrollBar:GetName() .. "ScrollUpButton"]
        local downBtn = scrollBar.ScrollDownButton or scrollBar.Forward or _G[scrollBar:GetName() .. "ScrollDownButton"]
        if upBtn then upBtn:SetAlpha(0) upBtn:EnableMouse(false) end
        if downBtn then downBtn:SetAlpha(0) downBtn:EnableMouse(false) end
    end

    -- Content frame (scroll child)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(contentWidth - PICKER_PADDING, 100) -- Height will be adjusted dynamically
    scrollFrame:SetScrollChild(content)
    frame.Content = content

    -- Button pool for font options
    frame.Buttons = {}

    -- Store accent colors for button styling
    frame._accentR = accentR
    frame._accentG = accentG
    frame._accentB = accentB

    -- Escape key to close
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            CloseFontPicker()
        end
    end)

    -- Click outside to close
    frame:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", function(self, elapsed)
            if not self:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                C_Timer.After(0.05, function()
                    if fontPickerFrame and fontPickerFrame:IsShown() and not fontPickerFrame:IsMouseOver() then
                        CloseFontPicker()
                    end
                end)
            end
        end)
    end)
    frame:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    fontPickerFrame = frame
    return frame
end

local function PopulateFontPicker(currentValue)
    local frame = fontPickerFrame
    if not frame then return end

    local content = frame.Content
    local displayNames = addon.FontDisplayNames or {}

    -- Get font options
    local fontOptions = {}

    -- Stock fonts first
    table.insert(fontOptions, { value = "FRIZQT__", text = displayNames.FRIZQT__ or "FRIZQT__" })
    local stockFonts = { "ARIALN", "MORPHEUS", "SKURRI" }
    for _, k in ipairs(stockFonts) do
        table.insert(fontOptions, { value = k, text = displayNames[k] or k })
    end

    -- Custom fonts sorted alphabetically
    local customEntries = {}
    for k, _ in pairs(addon.Fonts or {}) do
        if k ~= "FRIZQT__" and k ~= "ARIALN" and k ~= "MORPHEUS" and k ~= "SKURRI" then
            local display = displayNames[k] or k
            table.insert(customEntries, { value = k, text = display })
        end
    end
    table.sort(customEntries, function(a, b) return a.text < b.text end)
    for _, entry in ipairs(customEntries) do
        table.insert(fontOptions, entry)
    end

    -- Calculate content height
    local numRows = math.ceil(#fontOptions / FONTS_PER_ROW)
    local contentHeight = (numRows * FONT_BUTTON_HEIGHT) + ((numRows - 1) * FONT_BUTTON_SPACING) + PICKER_PADDING
    content:SetHeight(contentHeight)

    -- Hide all existing buttons first
    for _, btn in ipairs(frame.Buttons) do
        btn:Hide()
    end

    -- Get default font for fallback
    local defaultFont = select(1, _G.GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF"

    -- Get accent colors from frame
    local accentR = frame._accentR or BRAND_R
    local accentG = frame._accentG or BRAND_G
    local accentB = frame._accentB or BRAND_B

    -- Create/reuse buttons for each font option (TUI style: no backgrounds, clean text)
    for i, option in ipairs(fontOptions) do
        local btn = frame.Buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, content)
            btn:SetSize(FONT_BUTTON_WIDTH, FONT_BUTTON_HEIGHT)

            -- Create label with GameFontNormalSmall as template for initial font
            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", btn, "LEFT", 4, 0)
            label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            btn.Label = label

            frame.Buttons[i] = btn
        end

        -- Position button in grid
        local col = (i - 1) % FONTS_PER_ROW
        local row = math.floor((i - 1) / FONTS_PER_ROW)
        local x = col * (FONT_BUTTON_WIDTH + FONT_BUTTON_SPACING)
        local y = -(row * (FONT_BUTTON_HEIGHT + FONT_BUTTON_SPACING))
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)

        -- Set font FIRST (before text) - try custom font, fall back to default
        local fontFace = addon.ResolveFontFace(option.value)
        local fontSet = false
        if fontFace then
            fontSet = pcall(btn.Label.SetFont, btn.Label, fontFace, 12, "")
        end
        if not fontSet then
            -- Fallback to default font if custom font failed
            pcall(btn.Label.SetFont, btn.Label, defaultFont, 12, "")
        end

        -- Now set text (font is guaranteed to be set)
        btn.Label:SetText(option.text)

        -- Set text color based on selected state (TUI style: accent for selected, white for unselected)
        local isSelected = (currentValue == option.value)
        if isSelected then
            btn.Label:SetTextColor(accentR, accentG, accentB, 1)
        else
            btn.Label:SetTextColor(1, 1, 1, 0.9)
        end

        -- Store option data and selected state
        btn._fontValue = option.value
        btn._fontText = option.text
        btn._isSelected = isSelected
        btn._accentR = accentR
        btn._accentG = accentG
        btn._accentB = accentB

        -- Click handler
        btn:SetScript("OnClick", function(self)
            local value = self._fontValue
            if fontPickerSetting and fontPickerSetting.SetValue then
                fontPickerSetting:SetValue(value)
            end
            if fontPickerCallback then
                fontPickerCallback(value)
            end
            -- Update dropdown text if anchor exists
            if fontPickerAnchor and fontPickerAnchor.Text then
                local displayText = addon.FontDisplayNames and addon.FontDisplayNames[value] or value
                fontPickerAnchor.Text:SetText(displayText)
            end
            CloseFontPicker()
        end)

        -- Hover effects (TUI style: accent color on hover)
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

function addon.ShowFontPicker(anchor, setting, optionsProvider, callback)
    local frame = CreateFontPicker()

    fontPickerSetting = setting
    fontPickerCallback = callback
    fontPickerAnchor = anchor

    -- Get current value
    local currentValue = nil
    if setting and setting.GetValue then
        currentValue = setting:GetValue()
    end

    -- Populate the picker
    PopulateFontPicker(currentValue)

    -- Position relative to anchor
    frame:ClearAllPoints()
    if anchor then
        -- Try to position below the anchor, but adjust if it would go off screen
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

    -- Preload fonts for smooth rendering
    if addon.PreloadFonts then
        addon.PreloadFonts()
                        end
                    end

function addon.CloseFontPicker()
    CloseFontPicker()
end

--------------------------------------------------------------------------------
-- Font Dropdown Integration
--------------------------------------------------------------------------------

-- Apply font preview to a Settings dropdown by using our custom font picker popup
function addon.InitFontDropdown(dropdown, setting, optionsProvider)
    if not dropdown or dropdown._ScootFontPickerInit then return end

    -- Function to update dropdown display text
    local function updateDropdownText()
        if not setting or not setting.GetValue then return end
        local currentValue = setting:GetValue()
        local displayText = addon.FontDisplayNames and addon.FontDisplayNames[currentValue] or currentValue
        if dropdown.Text and dropdown.Text.SetText then
            dropdown.Text:SetText(displayText)
            -- Also render the dropdown text in the selected font
            local fontFace = addon.ResolveFontFace(currentValue)
            if fontFace then
                pcall(dropdown.Text.SetFont, dropdown.Text, fontFace, 12, "")
            end
        end
    end

    -- Intercept clicks to show our custom picker instead of Blizzard's menu
    local function showPicker()
        -- Close any open Blizzard menus first
        if _G.MenuUtil and _G.MenuUtil.HideAllMenus then
            pcall(_G.MenuUtil.HideAllMenus)
        end
        if _G.CloseDropDownMenus then
            pcall(_G.CloseDropDownMenus)
        end

        addon.ShowFontPicker(dropdown, setting, optionsProvider, function(selectedValue)
            -- Callback after selection - update display
            updateDropdownText()
        end)
    end

    -- Create an invisible overlay button that captures clicks before the dropdown
    local overlay = CreateFrame("Button", nil, dropdown)
    overlay:SetAllPoints(dropdown)
    overlay:SetFrameLevel(dropdown:GetFrameLevel() + 10)
    overlay:RegisterForClicks("LeftButtonUp", "LeftButtonDown")

    overlay:SetScript("OnClick", function(self, button, down)
        if not down then
            showPicker()
        end
    end)

    -- Make overlay transparent but clickable
    overlay:EnableMouse(true)

    -- Store reference so we can access it later if needed
    dropdown._ScootFontPickerOverlay = overlay

    -- Initial text update
    C_Timer.After(0, updateDropdownText)

    dropdown._ScootFontPickerInit = true
end

-- Register stock faces and bundled font variants (paths are relative to the WoW root)
do
    local f = addon.Fonts
    -- Blizzard stock font aliases
    f.FRIZQT__ = "Fonts\\FRIZQT__.TTF"
    f.ARIALN   = "Fonts\\ARIALN.TTF"
    f.MORPHEUS = "Fonts\\MORPHEUS.TTF"
    f.SKURRI   = "Fonts\\SKURRI.TTF"

    local base = "Interface\\AddOns\\Scoot\\media\\fonts\\"

    -- Fira Sans family
    f.FIRASANS_REG             = base .. "FiraSans-Regular.ttf"
    f.FIRASANS_ITALIC          = base .. "FiraSans-Italic.ttf"
    f.FIRASANS_LIGHT           = base .. "FiraSans-Light.ttf"
    f.FIRASANS_LIGHTITALIC     = base .. "FiraSans-LightItalic.ttf"
    f.FIRASANS_MED             = base .. "FiraSans-Medium.ttf"
    f.FIRASANS_MEDITALIC       = base .. "FiraSans-MediumItalic.ttf"
    f.FIRASANS_SEMIBOLD        = base .. "FiraSans-SemiBold.ttf"
    f.FIRASANS_SEMIBOLDITALIC  = base .. "FiraSans-SemiBoldItalic.ttf"
    f.FIRASANS_BOLD            = base .. "FiraSans-Bold.ttf"
    f.FIRASANS_BOLDITALIC      = base .. "FiraSans-BoldItalic.ttf"
    f.FIRASANS_EXTRABOLD       = base .. "FiraSans-ExtraBold.ttf"
    f.FIRASANS_EXTRABOLDITALIC = base .. "FiraSans-ExtraBoldItalic.ttf"
    f.FIRASANS_BLACK           = base .. "FiraSans-Black.ttf"
    f.FIRASANS_BLACKITALIC     = base .. "FiraSans-BlackItalic.ttf"
    f.FIRASANS_EXTRALIGHT      = base .. "FiraSans-ExtraLight.ttf"
    f.FIRASANS_EXTRALIGHTITALIC= base .. "FiraSans-ExtraLightItalic.ttf"
    f.FIRASANS_THIN            = base .. "FiraSans-Thin.ttf"
    f.FIRASANS_THINITALIC      = base .. "FiraSans-ThinItalic.ttf"

    -- Roboto family (full)
    f.ROBOTO_REG             = base .. "Roboto-Regular.ttf"
    f.ROBOTO_ITALIC          = base .. "Roboto-Italic.ttf"
    f.ROBOTO_LIGHT           = base .. "Roboto-Light.ttf"
    f.ROBOTO_LIGHTITALIC     = base .. "Roboto-LightItalic.ttf"
    f.ROBOTO_MED             = base .. "Roboto-Medium.ttf"
    f.ROBOTO_MEDITALIC       = base .. "Roboto-MediumItalic.ttf"
    f.ROBOTO_SEMIBOLD        = base .. "Roboto-SemiBold.ttf"
    f.ROBOTO_SEMIBOLDITALIC  = base .. "Roboto-SemiBoldItalic.ttf"
    f.ROBOTO_BLD             = base .. "Roboto-Bold.ttf"
    f.ROBOTO_BOLDITALIC      = base .. "Roboto-BoldItalic.ttf"
    f.ROBOTO_EXTRABOLD       = base .. "Roboto-ExtraBold.ttf"
    f.ROBOTO_EXTRABOLDITALIC = base .. "Roboto-ExtraBoldItalic.ttf"
    f.ROBOTO_BLACK           = base .. "Roboto-Black.ttf"
    f.ROBOTO_BLACKITALIC     = base .. "Roboto-BlackItalic.ttf"
    f.ROBOTO_EXTRALIGHT      = base .. "Roboto-ExtraLight.ttf"
    f.ROBOTO_EXTRALIGHTITALIC= base .. "Roboto-ExtraLightItalic.ttf"
    f.ROBOTO_THIN            = base .. "Roboto-Thin.ttf"
    f.ROBOTO_THINITALIC      = base .. "Roboto-ThinItalic.ttf"

    -- Roboto Condensed family
    f.ROBOTO_COND_REG             = base .. "Roboto_Condensed-Regular.ttf"
    f.ROBOTO_COND_ITALIC          = base .. "Roboto_Condensed-Italic.ttf"
    f.ROBOTO_COND_LIGHT           = base .. "Roboto_Condensed-Light.ttf"
    f.ROBOTO_COND_LIGHTITALIC     = base .. "Roboto_Condensed-LightItalic.ttf"
    f.ROBOTO_COND_MED             = base .. "Roboto_Condensed-Medium.ttf"
    f.ROBOTO_COND_MEDITALIC       = base .. "Roboto_Condensed-MediumItalic.ttf"
    f.ROBOTO_COND_SEMIBOLD        = base .. "Roboto_Condensed-SemiBold.ttf"
    f.ROBOTO_COND_SEMIBOLDITALIC  = base .. "Roboto_Condensed-SemiBoldItalic.ttf"
    f.ROBOTO_COND_BOLD            = base .. "Roboto_Condensed-Bold.ttf"
    f.ROBOTO_COND_BOLDITALIC      = base .. "Roboto_Condensed-BoldItalic.ttf"
    f.ROBOTO_COND_EXTRABOLD       = base .. "Roboto_Condensed-ExtraBold.ttf"
    f.ROBOTO_COND_EXTRABOLDITALIC = base .. "Roboto_Condensed-ExtraBoldItalic.ttf"
    f.ROBOTO_COND_BLACK           = base .. "Roboto_Condensed-Black.ttf"
    f.ROBOTO_COND_BLACKITALIC     = base .. "Roboto_Condensed-BlackItalic.ttf"
    f.ROBOTO_COND_EXTRALIGHT      = base .. "Roboto_Condensed-ExtraLight.ttf"
    f.ROBOTO_COND_EXTRALIGHTITALIC= base .. "Roboto_Condensed-ExtraLightItalic.ttf"
    f.ROBOTO_COND_THIN            = base .. "Roboto_Condensed-Thin.ttf"
    f.ROBOTO_COND_THINITALIC      = base .. "Roboto_Condensed-ThinItalic.ttf"

    -- Roboto SemiCondensed family
    f.ROBOTO_SEMICOND_REG             = base .. "Roboto_SemiCondensed-Regular.ttf"
    f.ROBOTO_SEMICOND_ITALIC          = base .. "Roboto_SemiCondensed-Italic.ttf"
    f.ROBOTO_SEMICOND_LIGHT           = base .. "Roboto_SemiCondensed-Light.ttf"
    f.ROBOTO_SEMICOND_LIGHTITALIC     = base .. "Roboto_SemiCondensed-LightItalic.ttf"
    f.ROBOTO_SEMICOND_MED             = base .. "Roboto_SemiCondensed-Medium.ttf"
    f.ROBOTO_SEMICOND_MEDITALIC       = base .. "Roboto_SemiCondensed-MediumItalic.ttf"
    f.ROBOTO_SEMICOND_SEMIBOLD        = base .. "Roboto_SemiCondensed-SemiBold.ttf"
    f.ROBOTO_SEMICOND_SEMIBOLDITALIC  = base .. "Roboto_SemiCondensed-SemiBoldItalic.ttf"
    f.ROBOTO_SEMICOND_BOLD            = base .. "Roboto_SemiCondensed-Bold.ttf"
    f.ROBOTO_SEMICOND_BOLDITALIC      = base .. "Roboto_SemiCondensed-BoldItalic.ttf"
    f.ROBOTO_SEMICOND_EXTRABOLD       = base .. "Roboto_SemiCondensed-ExtraBold.ttf"
    f.ROBOTO_SEMICOND_EXTRABOLDITALIC = base .. "Roboto_SemiCondensed-ExtraBoldItalic.ttf"
    f.ROBOTO_SEMICOND_BLACK           = base .. "Roboto_SemiCondensed-Black.ttf"
    f.ROBOTO_SEMICOND_BLACKITALIC     = base .. "Roboto_SemiCondensed-BlackItalic.ttf"
    f.ROBOTO_SEMICOND_EXTRALIGHT      = base .. "Roboto_SemiCondensed-ExtraLight.ttf"
    f.ROBOTO_SEMICOND_EXTRALIGHTITALIC= base .. "Roboto_SemiCondensed-ExtraLightItalic.ttf"
    f.ROBOTO_SEMICOND_THIN            = base .. "Roboto_SemiCondensed-Thin.ttf"
    f.ROBOTO_SEMICOND_THINITALIC      = base .. "Roboto_SemiCondensed-ThinItalic.ttf"

    -- Dosis family
    f.DOSIS_BOLD       = base .. "Dosis-Bold.ttf"
    f.DOSIS_EXTRABOLD  = base .. "Dosis-ExtraBold.ttf"
    f.DOSIS_EXTRALIGHT = base .. "Dosis-ExtraLight.ttf"
    f.DOSIS_LIGHT      = base .. "Dosis-Light.ttf"
    f.DOSIS_MED        = base .. "Dosis-Medium.ttf"
    f.DOSIS_REG        = base .. "Dosis-Regular.ttf"
    f.DOSIS_SEMIBOLD   = base .. "Dosis-SemiBold.ttf"

    -- Exo2 family
    f.EXO2_BLACK           = base .. "Exo2-Black.ttf"
    f.EXO2_BLACKITALIC     = base .. "Exo2-BlackItalic.ttf"
    f.EXO2_BOLD            = base .. "Exo2-Bold.ttf"
    f.EXO2_BOLDITALIC      = base .. "Exo2-BoldItalic.ttf"
    f.EXO2_EXTRABOLD       = base .. "Exo2-ExtraBold.ttf"
    f.EXO2_EXTRABOLDITALIC = base .. "Exo2-ExtraBoldItalic.ttf"
    f.EXO2_EXTRALIGHT      = base .. "Exo2-ExtraLight.ttf"
    f.EXO2_EXTRALIGHTITALIC= base .. "Exo2-ExtraLightItalic.ttf"
    f.EXO2_ITALIC          = base .. "Exo2-Italic.ttf"
    f.EXO2_LIGHT           = base .. "Exo2-Light.ttf"
    f.EXO2_LIGHTITALIC     = base .. "Exo2-LightItalic.ttf"
    f.EXO2_MED             = base .. "Exo2-Medium.ttf"
    f.EXO2_MEDITALIC       = base .. "Exo2-MediumItalic.ttf"
    f.EXO2_REG             = base .. "Exo2-Regular.ttf"
    f.EXO2_SEMIBOLD        = base .. "Exo2-SemiBold.ttf"
    f.EXO2_SEMIBOLDITALIC  = base .. "Exo2-SemiBoldItalic.ttf"
    f.EXO2_THIN            = base .. "Exo2-Thin.ttf"
    f.EXO2_THINITALIC      = base .. "Exo2-ThinItalic.ttf"

    -- Lato family
    f.LATO_BLACK       = base .. "Lato-Black.ttf"
    f.LATO_BLACKITALIC = base .. "Lato-BlackItalic.ttf"
    f.LATO_BOLD        = base .. "Lato-Bold.ttf"
    f.LATO_BOLDITALIC  = base .. "Lato-BoldItalic.ttf"
    f.LATO_ITALIC      = base .. "Lato-Italic.ttf"
    f.LATO_LIGHT       = base .. "Lato-Light.ttf"
    f.LATO_LIGHTITALIC = base .. "Lato-LightItalic.ttf"
    f.LATO_REG         = base .. "Lato-Regular.ttf"
    f.LATO_THIN        = base .. "Lato-Thin.ttf"
    f.LATO_THINITALIC  = base .. "Lato-ThinItalic.ttf"

    -- Montserrat family
    f.MONTSERRAT_BLACK           = base .. "Montserrat-Black.ttf"
    f.MONTSERRAT_BLACKITALIC     = base .. "Montserrat-BlackItalic.ttf"
    f.MONTSERRAT_BOLD            = base .. "Montserrat-Bold.ttf"
    f.MONTSERRAT_BOLDITALIC      = base .. "Montserrat-BoldItalic.ttf"
    f.MONTSERRAT_EXTRABOLD       = base .. "Montserrat-ExtraBold.ttf"
    f.MONTSERRAT_EXTRABOLDITALIC = base .. "Montserrat-ExtraBoldItalic.ttf"
    f.MONTSERRAT_EXTRALIGHT      = base .. "Montserrat-ExtraLight.ttf"
    f.MONTSERRAT_EXTRALIGHTITALIC= base .. "Montserrat-ExtraLightItalic.ttf"
    f.MONTSERRAT_ITALIC          = base .. "Montserrat-Italic.ttf"
    f.MONTSERRAT_LIGHT           = base .. "Montserrat-Light.ttf"
    f.MONTSERRAT_LIGHTITALIC     = base .. "Montserrat-LightItalic.ttf"
    f.MONTSERRAT_MED             = base .. "Montserrat-Medium.ttf"
    f.MONTSERRAT_MEDITALIC       = base .. "Montserrat-MediumItalic.ttf"
    f.MONTSERRAT_REG             = base .. "Montserrat-Regular.ttf"
    f.MONTSERRAT_SEMIBOLD        = base .. "Montserrat-SemiBold.ttf"
    f.MONTSERRAT_SEMIBOLDITALIC  = base .. "Montserrat-SemiBoldItalic.ttf"
    f.MONTSERRAT_THIN            = base .. "Montserrat-Thin.ttf"
    f.MONTSERRAT_THINITALIC      = base .. "Montserrat-ThinItalic.ttf"

    -- Mukta family
    f.MUKTA_BOLD       = base .. "Mukta-Bold.ttf"
    f.MUKTA_EXTRABOLD  = base .. "Mukta-ExtraBold.ttf"
    f.MUKTA_EXTRALIGHT = base .. "Mukta-ExtraLight.ttf"
    f.MUKTA_LIGHT      = base .. "Mukta-Light.ttf"
    f.MUKTA_MED        = base .. "Mukta-Medium.ttf"
    f.MUKTA_REG        = base .. "Mukta-Regular.ttf"
    f.MUKTA_SEMIBOLD   = base .. "Mukta-SemiBold.ttf"

    -- Poppins family
    f.POPPINS_BLACK           = base .. "Poppins-Black.ttf"
    f.POPPINS_BLACKITALIC     = base .. "Poppins-BlackItalic.ttf"
    f.POPPINS_BOLD            = base .. "Poppins-Bold.ttf"
    f.POPPINS_BOLDITALIC      = base .. "Poppins-BoldItalic.ttf"
    f.POPPINS_EXTRABOLD       = base .. "Poppins-ExtraBold.ttf"
    f.POPPINS_EXTRABOLDITALIC = base .. "Poppins-ExtraBoldItalic.ttf"
    f.POPPINS_EXTRALIGHT      = base .. "Poppins-ExtraLight.ttf"
    f.POPPINS_EXTRALIGHTITALIC= base .. "Poppins-ExtraLightItalic.ttf"
    f.POPPINS_ITALIC          = base .. "Poppins-Italic.ttf"
    f.POPPINS_LIGHT           = base .. "Poppins-Light.ttf"
    f.POPPINS_LIGHTITALIC     = base .. "Poppins-LightItalic.ttf"
    f.POPPINS_MED             = base .. "Poppins-Medium.ttf"
    f.POPPINS_MEDITALIC       = base .. "Poppins-MediumItalic.ttf"
    f.POPPINS_REG             = base .. "Poppins-Regular.ttf"
    f.POPPINS_SEMIBOLD        = base .. "Poppins-SemiBold.ttf"
    f.POPPINS_SEMIBOLDITALIC  = base .. "Poppins-SemiBoldItalic.ttf"
    f.POPPINS_THIN            = base .. "Poppins-Thin.ttf"
    f.POPPINS_THINITALIC      = base .. "Poppins-ThinItalic.ttf"
end

-- Human-readable display names for the font dropdown
addon.FontDisplayNames = {
    -- Stock fonts
    FRIZQT__  = "Friz Quadrata (Default)",
    ARIALN    = "Arial Narrow",
    MORPHEUS  = "Morpheus",
    SKURRI    = "Skurri",
    -- Fira Sans
    FIRASANS_REG             = "Fira Sans",
    FIRASANS_ITALIC          = "Fira Sans Italic",
    FIRASANS_LIGHT           = "Fira Sans Light",
    FIRASANS_LIGHTITALIC     = "Fira Sans Light Italic",
    FIRASANS_MED             = "Fira Sans Medium",
    FIRASANS_MEDITALIC       = "Fira Sans Medium Italic",
    FIRASANS_SEMIBOLD        = "Fira Sans SemiBold",
    FIRASANS_SEMIBOLDITALIC  = "Fira Sans SemiBold Italic",
    FIRASANS_BOLD            = "Fira Sans Bold",
    FIRASANS_BOLDITALIC      = "Fira Sans Bold Italic",
    FIRASANS_EXTRABOLD       = "Fira Sans ExtraBold",
    FIRASANS_EXTRABOLDITALIC = "Fira Sans ExtraBold Italic",
    FIRASANS_BLACK           = "Fira Sans Black",
    FIRASANS_BLACKITALIC     = "Fira Sans Black Italic",
    FIRASANS_EXTRALIGHT      = "Fira Sans ExtraLight",
    FIRASANS_EXTRALIGHTITALIC= "Fira Sans ExtraLight Italic",
    FIRASANS_THIN            = "Fira Sans Thin",
    FIRASANS_THINITALIC      = "Fira Sans Thin Italic",
    -- Roboto
    ROBOTO_REG             = "Roboto",
    ROBOTO_ITALIC          = "Roboto Italic",
    ROBOTO_LIGHT           = "Roboto Light",
    ROBOTO_LIGHTITALIC     = "Roboto Light Italic",
    ROBOTO_MED             = "Roboto Medium",
    ROBOTO_MEDITALIC       = "Roboto Medium Italic",
    ROBOTO_SEMIBOLD        = "Roboto SemiBold",
    ROBOTO_SEMIBOLDITALIC  = "Roboto SemiBold Italic",
    ROBOTO_BLD             = "Roboto Bold",
    ROBOTO_BOLDITALIC      = "Roboto Bold Italic",
    ROBOTO_EXTRABOLD       = "Roboto ExtraBold",
    ROBOTO_EXTRABOLDITALIC = "Roboto ExtraBold Italic",
    ROBOTO_BLACK           = "Roboto Black",
    ROBOTO_BLACKITALIC     = "Roboto Black Italic",
    ROBOTO_EXTRALIGHT      = "Roboto ExtraLight",
    ROBOTO_EXTRALIGHTITALIC= "Roboto ExtraLight Italic",
    ROBOTO_THIN            = "Roboto Thin",
    ROBOTO_THINITALIC      = "Roboto Thin Italic",
    -- Roboto Condensed
    ROBOTO_COND_REG             = "Roboto Cond",
    ROBOTO_COND_ITALIC          = "Roboto Cond Italic",
    ROBOTO_COND_LIGHT           = "Roboto Cond Light",
    ROBOTO_COND_LIGHTITALIC     = "Roboto Cond Light Italic",
    ROBOTO_COND_MED             = "Roboto Cond Medium",
    ROBOTO_COND_MEDITALIC       = "Roboto Cond Medium Italic",
    ROBOTO_COND_SEMIBOLD        = "Roboto Cond SemiBold",
    ROBOTO_COND_SEMIBOLDITALIC  = "Roboto Cond SemiBold Italic",
    ROBOTO_COND_BOLD            = "Roboto Cond Bold",
    ROBOTO_COND_BOLDITALIC      = "Roboto Cond Bold Italic",
    ROBOTO_COND_EXTRABOLD       = "Roboto Cond ExtraBold",
    ROBOTO_COND_EXTRABOLDITALIC = "Roboto Cond ExtraBold Italic",
    ROBOTO_COND_BLACK           = "Roboto Cond Black",
    ROBOTO_COND_BLACKITALIC     = "Roboto Cond Black Italic",
    ROBOTO_COND_EXTRALIGHT      = "Roboto Cond ExtraLight",
    ROBOTO_COND_EXTRALIGHTITALIC= "Roboto Cond ExtraLight Italic",
    ROBOTO_COND_THIN            = "Roboto Cond Thin",
    ROBOTO_COND_THINITALIC      = "Roboto Cond Thin Italic",
    -- Roboto SemiCondensed
    ROBOTO_SEMICOND_REG             = "Roboto SemiCond",
    ROBOTO_SEMICOND_ITALIC          = "Roboto SemiCond Italic",
    ROBOTO_SEMICOND_LIGHT           = "Roboto SemiCond Light",
    ROBOTO_SEMICOND_LIGHTITALIC     = "Roboto SemiCond Light Italic",
    ROBOTO_SEMICOND_MED             = "Roboto SemiCond Medium",
    ROBOTO_SEMICOND_MEDITALIC       = "Roboto SemiCond Medium Italic",
    ROBOTO_SEMICOND_SEMIBOLD        = "Roboto SemiCond SemiBold",
    ROBOTO_SEMICOND_SEMIBOLDITALIC  = "Roboto SemiCond SemiBold Italic",
    ROBOTO_SEMICOND_BOLD            = "Roboto SemiCond Bold",
    ROBOTO_SEMICOND_BOLDITALIC      = "Roboto SemiCond Bold Italic",
    ROBOTO_SEMICOND_EXTRABOLD       = "Roboto SemiCond ExtraBold",
    ROBOTO_SEMICOND_EXTRABOLDITALIC = "Roboto SemiCond ExtraBold Italic",
    ROBOTO_SEMICOND_BLACK           = "Roboto SemiCond Black",
    ROBOTO_SEMICOND_BLACKITALIC     = "Roboto SemiCond Black Italic",
    ROBOTO_SEMICOND_EXTRALIGHT      = "Roboto SemiCond ExtraLight",
    ROBOTO_SEMICOND_EXTRALIGHTITALIC= "Roboto SemiCond ExtraLight Italic",
    ROBOTO_SEMICOND_THIN            = "Roboto SemiCond Thin",
    ROBOTO_SEMICOND_THINITALIC      = "Roboto SemiCond Thin Italic",
    -- Dosis
    DOSIS_REG        = "Dosis",
    DOSIS_LIGHT      = "Dosis Light",
    DOSIS_MED        = "Dosis Medium",
    DOSIS_SEMIBOLD   = "Dosis SemiBold",
    DOSIS_BOLD       = "Dosis Bold",
    DOSIS_EXTRABOLD  = "Dosis ExtraBold",
    DOSIS_EXTRALIGHT = "Dosis ExtraLight",
    -- Exo2
    EXO2_REG             = "Exo 2",
    EXO2_ITALIC          = "Exo 2 Italic",
    EXO2_LIGHT           = "Exo 2 Light",
    EXO2_LIGHTITALIC     = "Exo 2 Light Italic",
    EXO2_MED             = "Exo 2 Medium",
    EXO2_MEDITALIC       = "Exo 2 Medium Italic",
    EXO2_SEMIBOLD        = "Exo 2 SemiBold",
    EXO2_SEMIBOLDITALIC  = "Exo 2 SemiBold Italic",
    EXO2_BOLD            = "Exo 2 Bold",
    EXO2_BOLDITALIC      = "Exo 2 Bold Italic",
    EXO2_EXTRABOLD       = "Exo 2 ExtraBold",
    EXO2_EXTRABOLDITALIC = "Exo 2 ExtraBold Italic",
    EXO2_BLACK           = "Exo 2 Black",
    EXO2_BLACKITALIC     = "Exo 2 Black Italic",
    EXO2_EXTRALIGHT      = "Exo 2 ExtraLight",
    EXO2_EXTRALIGHTITALIC= "Exo 2 ExtraLight Italic",
    EXO2_THIN            = "Exo 2 Thin",
    EXO2_THINITALIC      = "Exo 2 Thin Italic",
    -- Lato
    LATO_REG         = "Lato",
    LATO_ITALIC      = "Lato Italic",
    LATO_LIGHT       = "Lato Light",
    LATO_LIGHTITALIC = "Lato Light Italic",
    LATO_BOLD        = "Lato Bold",
    LATO_BOLDITALIC  = "Lato Bold Italic",
    LATO_BLACK       = "Lato Black",
    LATO_BLACKITALIC = "Lato Black Italic",
    LATO_THIN        = "Lato Thin",
    LATO_THINITALIC  = "Lato Thin Italic",
    -- Montserrat
    MONTSERRAT_REG             = "Montserrat",
    MONTSERRAT_ITALIC          = "Montserrat Italic",
    MONTSERRAT_LIGHT           = "Montserrat Light",
    MONTSERRAT_LIGHTITALIC     = "Montserrat Light Italic",
    MONTSERRAT_MED             = "Montserrat Medium",
    MONTSERRAT_MEDITALIC       = "Montserrat Medium Italic",
    MONTSERRAT_SEMIBOLD        = "Montserrat SemiBold",
    MONTSERRAT_SEMIBOLDITALIC  = "Montserrat SemiBold Italic",
    MONTSERRAT_BOLD            = "Montserrat Bold",
    MONTSERRAT_BOLDITALIC      = "Montserrat Bold Italic",
    MONTSERRAT_EXTRABOLD       = "Montserrat ExtraBold",
    MONTSERRAT_EXTRABOLDITALIC = "Montserrat ExtraBold Italic",
    MONTSERRAT_BLACK           = "Montserrat Black",
    MONTSERRAT_BLACKITALIC     = "Montserrat Black Italic",
    MONTSERRAT_EXTRALIGHT      = "Montserrat ExtraLight",
    MONTSERRAT_EXTRALIGHTITALIC= "Montserrat ExtraLight Italic",
    MONTSERRAT_THIN            = "Montserrat Thin",
    MONTSERRAT_THINITALIC      = "Montserrat Thin Italic",
    -- Mukta
    MUKTA_REG        = "Mukta",
    MUKTA_LIGHT      = "Mukta Light",
    MUKTA_MED        = "Mukta Medium",
    MUKTA_SEMIBOLD   = "Mukta SemiBold",
    MUKTA_BOLD       = "Mukta Bold",
    MUKTA_EXTRABOLD  = "Mukta ExtraBold",
    MUKTA_EXTRALIGHT = "Mukta ExtraLight",
    -- Poppins
    POPPINS_REG             = "Poppins",
    POPPINS_ITALIC          = "Poppins Italic",
    POPPINS_LIGHT           = "Poppins Light",
    POPPINS_LIGHTITALIC     = "Poppins Light Italic",
    POPPINS_MED             = "Poppins Medium",
    POPPINS_MEDITALIC       = "Poppins Medium Italic",
    POPPINS_SEMIBOLD        = "Poppins SemiBold",
    POPPINS_SEMIBOLDITALIC  = "Poppins SemiBold Italic",
    POPPINS_BOLD            = "Poppins Bold",
    POPPINS_BOLDITALIC      = "Poppins Bold Italic",
    POPPINS_EXTRABOLD       = "Poppins ExtraBold",
    POPPINS_EXTRABOLDITALIC = "Poppins ExtraBold Italic",
    POPPINS_BLACK           = "Poppins Black",
    POPPINS_BLACKITALIC     = "Poppins Black Italic",
    POPPINS_EXTRALIGHT      = "Poppins ExtraLight",
    POPPINS_EXTRALIGHTITALIC= "Poppins ExtraLight Italic",
    POPPINS_THIN            = "Poppins Thin",
    POPPINS_THINITALIC      = "Poppins Thin Italic",
}


-- Preload font faces once to ensure consistent first-use rendering after game launch.
-- This avoids cases where certain Roboto variants appear unstyled until a second open.
function addon.PreloadFonts()
    if addon._fontsPreloaded then return end
    addon._fontsPreloaded = true
    local holder = CreateFrame("Frame")
    holder:Hide()
    local fs = holder:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local size = 14
    local warmup = "The quick brown fox jumps over the lazy dog 0123456789 !@#%^&*()[]{}"
    for _, path in pairs(addon.Fonts or {}) do
        if type(path) == "string" and path ~= "" then
            pcall(fs.SetFont, fs, path, size, "")
            fs:SetText(warmup)
            pcall(fs.GetStringWidth, fs)
            fs:SetText("")
        end
    end
end



