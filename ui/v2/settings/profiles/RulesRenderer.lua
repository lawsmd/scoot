-- RulesRenderer.lua - Profiles Rules settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Profiles = addon.UI.Settings.Profiles or {}
addon.UI.Settings.Profiles.Rules = {}

local Rules = addon.UI.Settings.Profiles.Rules
local SettingsBuilder = addon.UI.SettingsBuilder
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls

-- State management for this renderer
-- CLEANUP NOTE:
--   1. ClearContent() - Cleans up when navigating AWAY from Rules
--   2. Rules.Render() - Cleans up when re-rendering Rules (refresh)
-- Both are needed to ensure proper cleanup in all scenarios.
Rules._state = {
    editingRules = {},      -- Track which rules are in edit mode (keyed by rule.id)
    breadcrumbs = {},       -- Track partial breadcrumb selections (keyed by rule.id)
    cardFrames = {},        -- Recycled card frames
    dividerFrames = {},     -- Recycled divider frames
    currentControls = {},   -- Track created controls for cleanup (see CLEANUP note above)
}

-- Constants for Rules UI layout
local RULES_CARD_HEIGHT_DISPLAY = 130
local RULES_CARD_HEIGHT_EDIT = 340
local RULES_DIVIDER_HEIGHT = 24
local RULES_ADD_BUTTON_HEIGHT = 50
local RULES_EMPTY_STATE_HEIGHT = 80
local RULES_INDEX_BADGE_SIZE = 26
local RULES_CARD_LEFT_MARGIN = 44  -- Space for index badge
local RULES_CARD_RIGHT_MARGIN = 8
local RULES_CARD_PADDING = 12
local RULES_MAX_DISPLAY_BADGES = 3
local RULES_SPEC_BADGE_GAP = 12  -- Horizontal gap between spec badges
local RULES_SPEC_BADGE_MIN_WIDTH = 70  -- Minimum width for spec badges
local RULES_BREADCRUMB_HEIGHT = 30  -- Taller dropdowns for long text

--------------------------------------------------------------------------------
-- Rules: Spec Picker Popup
--------------------------------------------------------------------------------

local rulesSpecPickerFrame = nil
local rulesSpecPickerElements = {}

local function CloseSpecPicker()
    if rulesSpecPickerFrame then
        rulesSpecPickerFrame:Hide()
    end
end

local function ShowSpecPicker(anchor, rule, callback)
    -- Get theme colors
    local ar, ag, ab = Theme:GetAccentColor()
    local bgR, bgG, bgB, bgA = Theme:GetBackgroundSolidColor()
    local dimR, dimG, dimB = Theme:GetDimTextColor()
    local fontPath = Theme:GetFont("VALUE")
    local labelFont = Theme:GetFont("LABEL")
    local headerFont = Theme:GetFont("HEADER")

    -- Get spec data (this is an ARRAY of class entries, not a key-value table)
    local specBuckets = {}
    if addon.Rules and addon.Rules.GetSpecBuckets then
        specBuckets = addon.Rules:GetSpecBuckets() or {}
    end

    -- Get currently selected specs
    local selectedSpecs = {}
    if rule and rule.trigger and rule.trigger.specIds then
        for _, id in ipairs(rule.trigger.specIds) do
            selectedSpecs[id] = true
        end
    end

    -- Clean up previous elements
    for _, elem in ipairs(rulesSpecPickerElements) do
        if elem.Hide then elem:Hide() end
        if elem.SetParent then elem:SetParent(nil) end
    end
    wipe(rulesSpecPickerElements)

    -- Create frame if needed
    if not rulesSpecPickerFrame then
        local frame = CreateFrame("Frame", "ScootSpecPicker", UIParent, "BackdropTemplate")
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(200)
        frame:SetClampedToScreen(true)
        frame:EnableMouse(true)
        frame:Hide()

        -- ESC to close
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
        frame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                CloseSpecPicker()
                PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        rulesSpecPickerFrame = frame
    end

    local frame = rulesSpecPickerFrame

    -- Calculate content height first
    local specRowHeight = 20
    local classHeaderHeight = 22
    local classGap = 8
    local specsPerRow = 3
    local contentHeight = 0

    for _, classEntry in ipairs(specBuckets) do
        contentHeight = contentHeight + classHeaderHeight
        local specRows = math.ceil(#classEntry.specs / specsPerRow)
        contentHeight = contentHeight + (specRows * specRowHeight) + classGap
    end

    -- Frame sizing
    local frameWidth = 360
    local titleHeight = 28
    local bottomPadding = 44
    local maxContentHeight = 300
    local actualContentHeight = math.min(contentHeight, maxContentHeight)
    local frameHeight = titleHeight + actualContentHeight + bottomPadding + 12
    local needsScroll = contentHeight > maxContentHeight

    frame:SetSize(frameWidth, frameHeight)

    -- Position below anchor using absolute coordinates
    -- (relative anchoring doesn't work reliably for popup frames)
    frame:ClearAllPoints()
    local anchorLeft = anchor:GetLeft()
    local anchorBottom = anchor:GetBottom()
    local scale = frame:GetEffectiveScale()
    if anchorLeft and anchorBottom then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", anchorLeft, anchorBottom - 4)
    else
        -- Fallback: position near mouse
        local x, y = GetCursorPosition()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end

    -- Update backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    frame:SetBackdropColor(bgR, bgG, bgB, 0.98)
    frame:SetBackdropBorderColor(ar, ag, ab, 0.9)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    titleBar:SetHeight(titleHeight)
    table.insert(rulesSpecPickerElements, titleBar)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(ar, ag, ab, 0.15)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(headerFont, 12, "")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleText:SetText("Select Specializations")
    titleText:SetTextColor(ar, ag, ab, 1)

    -- Close button (X)
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    table.insert(rulesSpecPickerElements, closeBtn)

    local closeText = closeBtn:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(headerFont, 14, "")
    closeText:SetPoint("CENTER")
    closeText:SetText("×")
    closeText:SetTextColor(dimR, dimG, dimB, 1)

    closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.3, 0.3, 1) end)
    closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(dimR, dimG, dimB, 1) end)
    closeBtn:SetScript("OnClick", function()
        CloseSpecPicker()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end)

    -- Content area (with optional scroll)
    local contentParent
    local scrollFrame, scrollBar

    if needsScroll then
        -- Create scroll frame manually (no Blizzard template)
        scrollFrame = CreateFrame("ScrollFrame", nil, frame)
        scrollFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 6, -6)
        scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, bottomPadding)
        scrollFrame:EnableMouseWheel(true)
        table.insert(rulesSpecPickerElements, scrollFrame)

        local scrollContent = CreateFrame("Frame", nil, scrollFrame)
        scrollContent:SetSize(frameWidth - 24, contentHeight)
        scrollFrame:SetScrollChild(scrollContent)
        contentParent = scrollContent

        -- TUI-styled scrollbar
        scrollBar = CreateFrame("Frame", nil, frame)
        scrollBar:SetWidth(6)
        scrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(titleHeight + 8))
        scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, bottomPadding + 2)
        table.insert(rulesSpecPickerElements, scrollBar)

        local scrollTrack = scrollBar:CreateTexture(nil, "BACKGROUND")
        scrollTrack:SetAllPoints()
        scrollTrack:SetColorTexture(0.15, 0.15, 0.15, 0.8)

        local scrollThumb = CreateFrame("Frame", nil, scrollBar)
        scrollThumb:SetWidth(6)
        local thumbRatio = actualContentHeight / contentHeight
        local thumbHeight = math.max(20, scrollBar:GetHeight() * thumbRatio)
        scrollThumb:SetHeight(thumbHeight)
        scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, 0)

        local thumbTex = scrollThumb:CreateTexture(nil, "ARTWORK")
        thumbTex:SetAllPoints()
        thumbTex:SetColorTexture(ar, ag, ab, 0.6)
        scrollBar._thumb = scrollThumb
        scrollBar._thumbTex = thumbTex

        -- Scroll wheel handler
        local maxScroll = contentHeight - actualContentHeight
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local newScroll = math.max(0, math.min(maxScroll, current - (delta * 30)))
            self:SetVerticalScroll(newScroll)
            -- Update thumb position
            local scrollRatio = newScroll / maxScroll
            local trackHeight = scrollBar:GetHeight() - thumbHeight
            scrollThumb:ClearAllPoints()
            scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, -scrollRatio * trackHeight)
        end)
    else
        -- No scroll needed, content directly in frame
        contentParent = CreateFrame("Frame", nil, frame)
        contentParent:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 6, -6)
        contentParent:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -6, -6)
        contentParent:SetHeight(contentHeight)
        table.insert(rulesSpecPickerElements, contentParent)
    end

    -- Build spec list
    local yOffset = 0
    local specColWidth = 105

    for _, classEntry in ipairs(specBuckets) do
        -- Class header
        local classHeader = contentParent:CreateFontString(nil, "OVERLAY")
        classHeader:SetFont(labelFont, 11, "")
        classHeader:SetPoint("TOPLEFT", contentParent, "TOPLEFT", 0, yOffset)
        classHeader:SetText(classEntry.name or "Unknown")

        -- Class color
        local classColor = RAID_CLASS_COLORS[classEntry.file]
        if classColor then
            classHeader:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
        else
            classHeader:SetTextColor(ar, ag, ab, 1)
        end

        yOffset = yOffset - classHeaderHeight

        -- Specs
        local xOffset = 10
        local colCount = 0
        for _, spec in ipairs(classEntry.specs) do
            local specID = spec.specID

            local toggle = CreateFrame("Button", nil, contentParent)
            toggle:SetSize(specColWidth, specRowHeight)
            toggle:SetPoint("TOPLEFT", contentParent, "TOPLEFT", xOffset, yOffset)
            toggle._selected = selectedSpecs[specID] or false

            -- Checkbox
            local checkbox = toggle:CreateTexture(nil, "ARTWORK")
            checkbox:SetSize(12, 12)
            checkbox:SetPoint("LEFT", toggle, "LEFT", 0, 0)
            checkbox:SetTexture("Interface\\Buttons\\WHITE8x8")
            toggle._checkbox = checkbox

            -- Icon
            local icon = toggle:CreateTexture(nil, "ARTWORK")
            icon:SetSize(14, 14)
            icon:SetPoint("LEFT", checkbox, "RIGHT", 3, 0)
            if spec.icon then icon:SetTexture(spec.icon) end

            -- Name
            local nameText = toggle:CreateFontString(nil, "OVERLAY")
            nameText:SetFont(fontPath, 10, "")
            nameText:SetPoint("LEFT", icon, "RIGHT", 3, 0)
            nameText:SetText(spec.name or "")
            nameText:SetWidth(specColWidth - 35)
            nameText:SetJustifyH("LEFT")
            toggle._nameText = nameText

            local function updateVisual()
                if toggle._selected then
                    checkbox:SetColorTexture(ar, ag, ab, 1)
                    nameText:SetTextColor(1, 1, 1, 1)
                else
                    checkbox:SetColorTexture(0.25, 0.25, 0.25, 1)
                    nameText:SetTextColor(dimR, dimG, dimB, 1)
                end
            end
            updateVisual()

            toggle:SetScript("OnEnter", function(self)
                if not self._selected then checkbox:SetColorTexture(ar, ag, ab, 0.5) end
            end)
            toggle:SetScript("OnLeave", function() updateVisual() end)
            toggle:SetScript("OnClick", function(self)
                self._selected = not self._selected
                updateVisual()
                if addon.Rules and addon.Rules.ToggleRuleSpec then
                    addon.Rules:ToggleRuleSpec(rule.id, specID)
                end
                if callback then callback() end
                PlaySound(self._selected and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
            end)

            colCount = colCount + 1
            if colCount >= specsPerRow then
                colCount = 0
                xOffset = 10
                yOffset = yOffset - specRowHeight
            else
                xOffset = xOffset + specColWidth
            end
        end

        -- Advance to next row if the last row was incomplete
        if colCount > 0 then
            yOffset = yOffset - specRowHeight
        end
        yOffset = yOffset - classGap
    end

    -- Done button
    local doneBtn = Controls:CreateButton({
        parent = frame,
        text = "Done",
        width = 80,
        height = 26,
        onClick = function()
            CloseSpecPicker()
            PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        end,
    })
    doneBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
    table.insert(rulesSpecPickerElements, doneBtn)

    frame:Show()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
end

--------------------------------------------------------------------------------
-- Rules: Spec Badge (icon + class-colored text, no background)
--------------------------------------------------------------------------------

local function CreateRulesSpecBadge(parent, specID)
    if not parent or not specID then return nil end
    if not addon.Rules or not addon.Rules.GetSpecBuckets then return nil end

    local _, specById = addon.Rules:GetSpecBuckets()
    local specEntry = specById and specById[specID]
    if not specEntry then return nil end

    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(90, 20)
    badge.specID = specID
    badge.specEntry = specEntry

    -- Spec icon
    local icon = badge:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", badge, "LEFT", 0, 0)
    if specEntry.icon then
        icon:SetTexture(specEntry.icon)
    end
    badge._icon = icon

    -- Spec name in class color (NO background per HOLDING3.md)
    local name = badge:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("VALUE")
    name:SetFont(fontPath, 11, "")
    name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    name:SetText(specEntry.name or tostring(specID))
    name:SetJustifyH("LEFT")

    -- Apply class color to text
    local classFile = specEntry.file or specEntry.classFile
    if classFile then
        local classColor = RAID_CLASS_COLORS[classFile]
        if classColor then
            name:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
        else
            name:SetTextColor(1, 1, 1, 1)
        end
    else
        name:SetTextColor(1, 1, 1, 1)
    end
    badge._name = name

    -- Size based on text width (synchronous for correct positioning)
    local textWidth = name:GetStringWidth() or 60
    local badgeWidth = math.max(RULES_SPEC_BADGE_MIN_WIDTH, 20 + textWidth + 8)
    badge:SetWidth(badgeWidth)

    -- Tooltip
    badge:EnableMouse(true)
    badge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(specEntry.className or "Unknown Class", 1, 1, 1)
        GameTooltip:AddLine(specEntry.name or "Unknown Spec", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return badge
end

--------------------------------------------------------------------------------
-- Rules: Format action value for display
--------------------------------------------------------------------------------

local function FormatRulesActionValue(actionId, value)
    if not addon.Rules then
        return tostring(value or "?"), nil
    end

    local meta = addon.Rules:GetActionMetadata(actionId)
    if not meta then
        return tostring(value or "?"), nil
    end

    local widget = meta.widget or "checkbox"
    local valueType = meta.valueType or "boolean"

    if widget == "checkbox" or valueType == "boolean" then
        return value and "True" or "False", nil
    elseif widget == "slider" or valueType == "number" then
        local num = tonumber(value) or 0
        if meta.uiMeta and meta.uiMeta.format == "percent" then
            return string.format("%d%%", num), nil
        end
        return tostring(num), nil
    elseif widget == "dropdown" then
        if meta.uiMeta and meta.uiMeta.values then
            local displayLabel = meta.uiMeta.values[value]
            if displayLabel then
                return displayLabel, nil
            end
        end
        return tostring(value or "?"), nil
    elseif widget == "color" or valueType == "color" then
        local colorValue = value
        if type(colorValue) ~= "table" then
            colorValue = { 1, 1, 1, 1 }
        end
        return nil, colorValue
    else
        return tostring(value or "?"), nil
    end
end

--------------------------------------------------------------------------------
-- Rules: Get action leaf name and parent path
--------------------------------------------------------------------------------

local function GetRulesActionLeafAndPath(actionId)
    if not addon.Rules then return "Select Target", "" end
    local meta = addon.Rules:GetActionMetadata(actionId)
    if not meta or not meta.path then
        return "Select Target", ""
    end
    local path = meta.path
    local leaf = path[#path] or "Unknown"
    local parentPath = ""
    if #path > 1 then
        local parents = {}
        for i = 1, #path - 1 do
            table.insert(parents, path[i])
        end
        parentPath = table.concat(parents, " › ")
    end
    return leaf, parentPath
end

--------------------------------------------------------------------------------
-- Rules: Display Mode (collapsed card)
--------------------------------------------------------------------------------

local function RenderRulesCardDisplayMode(card, rule, refreshCallback, ar, ag, ab)
    local fontPath = Theme:GetFont("VALUE")
    local labelFont = Theme:GetFont("LABEL")
    local dimR, dimG, dimB = Theme:GetDimTextColor()
    local state = Rules._state

    -- === HEADER ROW ===
    -- Enable toggle (using text-based ON/OFF indicator like Toggle)
    local enableLabel = card:CreateFontString(nil, "OVERLAY")
    enableLabel:SetFont(labelFont, 11, "")
    enableLabel:SetPoint("TOPLEFT", card, "TOPLEFT", RULES_CARD_PADDING, -RULES_CARD_PADDING)
    enableLabel:SetText("Enabled?")
    enableLabel:SetTextColor(ar, ag, ab, 1)
    card._enableLabel = enableLabel

    -- ON/OFF indicator
    local indicator = CreateFrame("Frame", nil, card)
    indicator:SetSize(50, 20)
    indicator:SetPoint("LEFT", enableLabel, "RIGHT", 8, 0)

    local indicatorBorder = {}
    for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
        local tex = indicator:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(ar, ag, ab, 0.8)
        if side == "TOP" then
            tex:SetHeight(1)
            tex:SetPoint("TOPLEFT", 0, 0)
            tex:SetPoint("TOPRIGHT", 0, 0)
        elseif side == "BOTTOM" then
            tex:SetHeight(1)
            tex:SetPoint("BOTTOMLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", 0, 0)
        elseif side == "LEFT" then
            tex:SetWidth(1)
            tex:SetPoint("TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMLEFT", 0, 0)
        elseif side == "RIGHT" then
            tex:SetWidth(1)
            tex:SetPoint("TOPRIGHT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", 0, 0)
        end
        indicatorBorder[side] = tex
    end

    local indicatorBg = indicator:CreateTexture(nil, "BACKGROUND")
    indicatorBg:SetAllPoints()
    local isEnabled = rule.enabled ~= false
    if isEnabled then
        indicatorBg:SetColorTexture(ar, ag, ab, 1)
    else
        indicatorBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    end
    indicator._bg = indicatorBg

    local indicatorText = indicator:CreateFontString(nil, "OVERLAY")
    indicatorText:SetFont(fontPath, 11, "")
    indicatorText:SetPoint("CENTER")
    indicatorText:SetText(isEnabled and "ON" or "OFF")
    indicatorText:SetTextColor(isEnabled and 0.05 or dimR, isEnabled and 0.05 or dimG, isEnabled and 0.05 or dimB, 1)
    indicator._text = indicatorText

    -- Make indicator clickable
    indicator:EnableMouse(true)
    indicator:SetScript("OnMouseDown", function()
        if addon.Rules and addon.Rules.SetRuleEnabled then
            addon.Rules:SetRuleEnabled(rule.id, not isEnabled)
            if refreshCallback then refreshCallback() end
        end
    end)
    card._indicator = indicator

    -- Edit button
    local editBtn = Controls:CreateButton({
        parent = card,
        text = "Edit",
        width = 50,
        height = 22,
        borderWidth = 1,
        borderAlpha = 0.6,
        onClick = function()
            state.editingRules[rule.id] = true
            if refreshCallback then refreshCallback() end
        end,
    })
    editBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -RULES_CARD_PADDING, -RULES_CARD_PADDING)
    card._editBtn = editBtn

    -- === WHEN ROW ===
    local whenLabel = card:CreateFontString(nil, "OVERLAY")
    whenLabel:SetFont(labelFont, 13, "")
    whenLabel:SetPoint("TOPLEFT", card, "TOPLEFT", RULES_CARD_PADDING + 4, -42)
    whenLabel:SetText("WHEN")
    whenLabel:SetTextColor(ar, ag, ab, 1)
    card._whenLabel = whenLabel

    local triggerType = rule.trigger and rule.trigger.type or "specialization"

    if triggerType == "playerLevel" then
        -- Player Level display
        local levelText = card:CreateFontString(nil, "OVERLAY")
        levelText:SetFont(fontPath, 12, "")
        levelText:SetPoint("LEFT", whenLabel, "RIGHT", 16, 0)
        local levelVal = rule.trigger and rule.trigger.level
        if levelVal then
            levelText:SetText(string.format("Player Level = %d", levelVal))
        else
            levelText:SetText("Player Level = (not set)")
        end
        levelText:SetTextColor(1, 1, 1, 1)
        card._levelText = levelText
    else
        -- Spec badges container
        local specIds = rule.trigger and rule.trigger.specIds or {}
        local specContainer = CreateFrame("Frame", nil, card)
        specContainer:SetPoint("LEFT", whenLabel, "RIGHT", 16, 0)
        specContainer:SetSize(400, 20)
        card._specContainer = specContainer
        card._specBadges = {}

        local xOffset = 0
        local visibleCount = math.min(#specIds, RULES_MAX_DISPLAY_BADGES)

        for i = 1, visibleCount do
            local specID = specIds[i]
            local badge = CreateRulesSpecBadge(specContainer, specID)
            if badge then
                badge:SetPoint("LEFT", specContainer, "LEFT", xOffset, 0)
                badge:Show()
                table.insert(card._specBadges, badge)
                xOffset = xOffset + badge:GetWidth() + RULES_SPEC_BADGE_GAP
            end
        end

        -- Overflow indicator
        local overflowCount = #specIds - visibleCount
        if overflowCount > 0 then
            local overflow = card:CreateFontString(nil, "OVERLAY")
            overflow:SetFont(fontPath, 10, "")
            overflow:SetPoint("LEFT", specContainer, "LEFT", xOffset, 0)
            overflow:SetText(string.format("+%d more", overflowCount))
            overflow:SetTextColor(dimR, dimG, dimB, 1)
            card._overflow = overflow
        end

        -- No specs placeholder
        if #specIds == 0 then
            local noSpec = card:CreateFontString(nil, "OVERLAY")
            noSpec:SetFont(fontPath, 11, "")
            noSpec:SetPoint("LEFT", whenLabel, "RIGHT", 16, 0)
            noSpec:SetText("(no specs selected)")
            noSpec:SetTextColor(dimR, dimG, dimB, 1)
            card._noSpec = noSpec
        end
    end

    -- === DO ROW ===
    local doLabel = card:CreateFontString(nil, "OVERLAY")
    doLabel:SetFont(labelFont, 13, "")
    doLabel:SetPoint("TOPLEFT", whenLabel, "BOTTOMLEFT", 0, -20)
    doLabel:SetText("DO")
    doLabel:SetTextColor(ar, ag, ab, 1)
    card._doLabel = doLabel

    local actionId = rule.action and rule.action.id
    local leaf, parentPath = GetRulesActionLeafAndPath(actionId)
    local displayText, colorValue = FormatRulesActionValue(actionId, rule.action and rule.action.value)

    local actionText = card:CreateFontString(nil, "OVERLAY")
    actionText:SetFont(fontPath, 12, "")
    actionText:SetPoint("LEFT", doLabel, "RIGHT", 28, 0)

    if colorValue then
        actionText:SetText(string.format("%s =", leaf))
        actionText:SetTextColor(1, 1, 1, 1)

        -- Color swatch
        local swatch = CreateFrame("Frame", nil, card)
        swatch:SetSize(24, 14)
        swatch:SetPoint("LEFT", actionText, "RIGHT", 6, 0)
        local swatchBg = swatch:CreateTexture(nil, "ARTWORK")
        swatchBg:SetAllPoints()
        local r, g, b, a = colorValue[1] or 1, colorValue[2] or 1, colorValue[3] or 1, colorValue[4] or 1
        swatchBg:SetColorTexture(r, g, b, a)
        card._swatch = swatch
    else
        actionText:SetText(string.format("%s = %s", leaf, displayText or "?"))
        actionText:SetTextColor(1, 1, 1, 1)
    end
    card._actionText = actionText

    -- Parent path (muted, smaller)
    if parentPath and parentPath ~= "" then
        local pathText = card:CreateFontString(nil, "OVERLAY")
        pathText:SetFont(fontPath, 10, "")
        pathText:SetPoint("TOPLEFT", actionText, "BOTTOMLEFT", 0, -4)
        pathText:SetText("@ " .. parentPath)
        pathText:SetTextColor(dimR, dimG, dimB, 1)
        card._pathText = pathText
    end
end

--------------------------------------------------------------------------------
-- Rules: Edit Mode (expanded card)
--------------------------------------------------------------------------------

local function RenderRulesCardEditMode(card, rule, refreshCallback, ar, ag, ab)
    local fontPath = Theme:GetFont("VALUE")
    local labelFont = Theme:GetFont("LABEL")
    local headerFont = Theme:GetFont("HEADER")
    local dimR, dimG, dimB = Theme:GetDimTextColor()
    local bgR, bgG, bgB, bgA = Theme:GetCollapsibleBgColor()
    local state = Rules._state

    -- === HEADER ROW ===
    -- Delete button
    local deleteBtn = Controls:CreateButton({
        parent = card,
        text = "Delete",
        width = 60,
        height = 22,
        borderWidth = 1,
        borderAlpha = 0.6,
        onClick = function()
            if addon.Dialogs and addon.Dialogs.Show then
                addon.Dialogs:Show("SCOOT_DELETE_RULE", {
                    onAccept = function()
                        if rule.id and addon.Rules and addon.Rules.DeleteRule then
                            state.editingRules[rule.id] = nil
                            state.breadcrumbs[rule.id] = nil
                            addon.Rules:DeleteRule(rule.id)
                            if refreshCallback then refreshCallback() end
                        end
                    end,
                })
            end
        end,
    })
    deleteBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -RULES_CARD_PADDING - 60, -RULES_CARD_PADDING)
    card._deleteBtn = deleteBtn

    -- Done button
    local doneBtn = Controls:CreateButton({
        parent = card,
        text = "Done",
        width = 50,
        height = 22,
        borderWidth = 1,
        borderAlpha = 0.6,
        onClick = function()
            state.editingRules[rule.id] = nil
            if refreshCallback then refreshCallback() end
        end,
    })
    doneBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -RULES_CARD_PADDING, -RULES_CARD_PADDING)
    card._doneBtn = doneBtn

    -- === TRIGGER SECTION ===
    local triggerSection = CreateFrame("Frame", nil, card)
    triggerSection:SetPoint("TOPLEFT", card, "TOPLEFT", RULES_CARD_PADDING, -40)
    triggerSection:SetPoint("TOPRIGHT", card, "TOPRIGHT", -RULES_CARD_PADDING, -40)
    triggerSection:SetHeight(90)

    local triggerBg = triggerSection:CreateTexture(nil, "BACKGROUND")
    triggerBg:SetAllPoints()
    triggerBg:SetColorTexture(0.08, 0.08, 0.1, 0.8)
    triggerSection._bg = triggerBg
    card._triggerSection = triggerSection

    -- TRIGGER header
    local triggerHeader = triggerSection:CreateFontString(nil, "OVERLAY")
    triggerHeader:SetFont(headerFont, 14, "")
    triggerHeader:SetPoint("TOPLEFT", triggerSection, "TOPLEFT", 8, -8)
    triggerHeader:SetText("TRIGGER")
    triggerHeader:SetTextColor(ar, ag, ab, 1)

    -- Type label
    local typeLabel = triggerSection:CreateFontString(nil, "OVERLAY")
    typeLabel:SetFont(labelFont, 11, "")
    typeLabel:SetPoint("TOPLEFT", triggerHeader, "BOTTOMLEFT", 0, -12)
    typeLabel:SetText("Type:")
    typeLabel:SetTextColor(ar, ag, ab, 1)

    -- Type selector (using Controls:CreateSelector directly for compact layout)
    local triggerType = rule.trigger and rule.trigger.type or "specialization"
    local typeSelector = Controls:CreateDropdown({
        parent = triggerSection,
        values = {
            specialization = "Specialization",
            playerLevel = "Player Level",
        },
        order = { "specialization", "playerLevel" },
        get = function() return triggerType end,
        set = function(val)
            if addon.Rules and addon.Rules.SetRuleTriggerType then
                addon.Rules:SetRuleTriggerType(rule.id, val)
            end
            if refreshCallback then refreshCallback() end
        end,
        placeholder = "Select...",
        width = 140,
    })
    typeSelector:SetPoint("LEFT", typeLabel, "RIGHT", 8, 0)
    card._typeSelector = typeSelector

    -- Trigger type-specific content
    if triggerType == "specialization" then
        -- Specs label
        local specsLabel = triggerSection:CreateFontString(nil, "OVERLAY")
        specsLabel:SetFont(labelFont, 11, "")
        specsLabel:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -16)
        specsLabel:SetText("Specs:")
        specsLabel:SetTextColor(ar, ag, ab, 1)

        -- Add/Remove button
        local addSpecBtn = Controls:CreateButton({
            parent = triggerSection,
            text = "Add/Remove",
            width = 100,
            height = 22,
            borderWidth = 1,
            borderAlpha = 0.6,
            onClick = function(self)
                -- Open spec picker
                ShowSpecPicker(self, rule, refreshCallback)
            end,
        })
        addSpecBtn:SetPoint("LEFT", specsLabel, "RIGHT", 8, 0)
        card._addSpecBtn = addSpecBtn

        -- Spec badges in edit mode
        local specIds = rule.trigger and rule.trigger.specIds or {}
        local editSpecContainer = CreateFrame("Frame", nil, triggerSection)
        editSpecContainer:SetPoint("LEFT", addSpecBtn, "RIGHT", 12, 0)
        editSpecContainer:SetSize(280, 20)
        card._editSpecContainer = editSpecContainer
        card._editSpecBadges = {}

        local xOffset = 0
        local visibleCount = math.min(#specIds, RULES_MAX_DISPLAY_BADGES)
        for i = 1, visibleCount do
            local specID = specIds[i]
            local badge = CreateRulesSpecBadge(editSpecContainer, specID)
            if badge then
                badge:SetPoint("LEFT", editSpecContainer, "LEFT", xOffset, 0)
                badge:Show()
                table.insert(card._editSpecBadges, badge)
                xOffset = xOffset + badge:GetWidth() + RULES_SPEC_BADGE_GAP
            end
        end

        if #specIds - visibleCount > 0 then
            local overflow = triggerSection:CreateFontString(nil, "OVERLAY")
            overflow:SetFont(fontPath, 10, "")
            overflow:SetPoint("LEFT", editSpecContainer, "LEFT", xOffset, 0)
            overflow:SetText(string.format("+%d more", #specIds - visibleCount))
            overflow:SetTextColor(dimR, dimG, dimB, 1)
        end

    elseif triggerType == "playerLevel" then
        -- Level label
        local levelLabel = triggerSection:CreateFontString(nil, "OVERLAY")
        levelLabel:SetFont(labelFont, 11, "")
        levelLabel:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -16)
        levelLabel:SetText("Level:")
        levelLabel:SetTextColor(ar, ag, ab, 1)

        -- Level input
        local levelInput = CreateFrame("EditBox", nil, triggerSection, "InputBoxTemplate")
        levelInput:SetSize(60, 22)
        levelInput:SetPoint("LEFT", levelLabel, "RIGHT", 8, 0)
        levelInput:SetAutoFocus(false)
        levelInput:SetNumeric(true)
        levelInput:SetMaxLetters(3)
        local currentLevel = rule.trigger and rule.trigger.level
        levelInput:SetText(currentLevel and tostring(currentLevel) or "")
        levelInput:SetScript("OnEnterPressed", function(self)
            local val = tonumber(self:GetText())
            if addon.Rules and addon.Rules.SetRuleTriggerLevel then
                addon.Rules:SetRuleTriggerLevel(rule.id, val)
            end
            self:ClearFocus()
            if refreshCallback then refreshCallback() end
        end)
        levelInput:SetScript("OnEscapePressed", function(self)
            self:SetText(currentLevel and tostring(currentLevel) or "")
            self:ClearFocus()
        end)
        card._levelInput = levelInput
    end

    -- === TARGET SECTION ===
    local targetSection = CreateFrame("Frame", nil, card)
    targetSection:SetPoint("TOPLEFT", triggerSection, "BOTTOMLEFT", 0, -8)
    targetSection:SetPoint("TOPRIGHT", triggerSection, "BOTTOMRIGHT", 0, -8)
    targetSection:SetHeight(90)

    local targetBg = targetSection:CreateTexture(nil, "BACKGROUND")
    targetBg:SetAllPoints()
    targetBg:SetColorTexture(0.08, 0.08, 0.1, 0.8)
    card._targetSection = targetSection

    -- TARGET header
    local targetHeader = targetSection:CreateFontString(nil, "OVERLAY")
    targetHeader:SetFont(headerFont, 14, "")
    targetHeader:SetPoint("TOPLEFT", targetSection, "TOPLEFT", 8, -8)
    targetHeader:SetText("TARGET")
    targetHeader:SetTextColor(ar, ag, ab, 1)

    -- Target description
    local targetDesc = targetSection:CreateFontString(nil, "OVERLAY")
    targetDesc:SetFont(fontPath, 10, "")
    targetDesc:SetPoint("TOPLEFT", targetHeader, "BOTTOMLEFT", 0, -8)
    targetDesc:SetText("Select the setting you want this rule to modify:")
    targetDesc:SetTextColor(dimR, dimG, dimB, 1)

    -- Breadcrumb dropdowns
    local actionId = rule.action and rule.action.id
    local currentPath = {}
    if actionId and addon.Rules then
        currentPath = addon.Rules:GetActionPath(actionId) or {}
    end

    -- Initialize breadcrumb state
    local breadcrumbState = state.breadcrumbs[rule.id]
    if not breadcrumbState then
        if #currentPath > 0 then
            breadcrumbState = { currentPath[1], currentPath[2], currentPath[3], currentPath[4] }
        else
            breadcrumbState = {}
        end
        state.breadcrumbs[rule.id] = breadcrumbState
    end

    -- Helper to get options for a level
    local function getOptionsForLevel(level)
        local pathPrefix = {}
        for i = 1, level - 1 do
            if breadcrumbState[i] then
                table.insert(pathPrefix, breadcrumbState[i])
            end
        end
        local rawOptions = addon.Rules and addon.Rules:GetActionsAtPath(pathPrefix) or {}
        local opts = {}
        local order = {}
        for _, opt in ipairs(rawOptions) do
            opts[opt.text] = opt.text
            table.insert(order, opt.text)
        end
        return opts, order
    end

    -- Helper to handle breadcrumb change
    local function onBreadcrumbChange(level, selectedText)
        breadcrumbState[level] = selectedText
        for i = level + 1, 4 do
            breadcrumbState[i] = nil
        end
        state.breadcrumbs[rule.id] = breadcrumbState

        local fullPath = {}
        for i = 1, 4 do
            if breadcrumbState[i] then
                table.insert(fullPath, breadcrumbState[i])
            else
                break
            end
        end

        local newActionId = addon.Rules and addon.Rules:GetActionIdForPath(fullPath)
        if newActionId then
            state.breadcrumbs[rule.id] = nil
            if addon.Rules and addon.Rules.SetRuleAction then
                addon.Rules:SetRuleAction(rule.id, newActionId)
            end
        else
            rule.action = rule.action or {}
            rule.action.id = nil
        end

        if refreshCallback then refreshCallback() end
    end

    -- Create breadcrumb dropdowns
    local dropdownWidth = 130
    local dropdownGap = 8
    local xPos = 8
    card._breadcrumbs = {}

    for level = 1, 4 do
        local shouldShow = (level == 1) or (breadcrumbState[level - 1] ~= nil)
        if shouldShow then
            local opts, order = getOptionsForLevel(level)
            if #order > 0 or breadcrumbState[level] then
                local dropdown = Controls:CreateDropdown({
                    parent = targetSection,
                    values = opts,
                    order = order,
                    get = function() return breadcrumbState[level] end,
                    set = function(val)
                        onBreadcrumbChange(level, val)
                    end,
                    placeholder = "Select...",
                    width = dropdownWidth,
                    height = RULES_BREADCRUMB_HEIGHT,  -- Taller to accommodate wrapped text
                })
                dropdown:SetPoint("TOPLEFT", targetSection, "TOPLEFT", xPos, -50)
                table.insert(card._breadcrumbs, dropdown)
                xPos = xPos + dropdownWidth + dropdownGap

                -- Separator
                if level < 4 and breadcrumbState[level] then
                    local sep = targetSection:CreateFontString(nil, "OVERLAY")
                    sep:SetFont(labelFont, 14, "")
                    sep:SetPoint("LEFT", dropdown, "RIGHT", 4, 0)
                    sep:SetText(">")
                    sep:SetTextColor(ar, ag, ab, 1)
                    xPos = xPos + 20
                end
            end
        end
    end

    -- === ACTION SECTION ===
    local actionSection = CreateFrame("Frame", nil, card)
    actionSection:SetPoint("TOPLEFT", targetSection, "BOTTOMLEFT", 0, -8)
    actionSection:SetPoint("TOPRIGHT", targetSection, "BOTTOMRIGHT", 0, -8)
    actionSection:SetHeight(80)

    local actionBg = actionSection:CreateTexture(nil, "BACKGROUND")
    actionBg:SetAllPoints()
    actionBg:SetColorTexture(0.08, 0.08, 0.1, 0.8)
    card._actionSection = actionSection

    -- ACTION header
    local actionHeader = actionSection:CreateFontString(nil, "OVERLAY")
    actionHeader:SetFont(headerFont, 14, "")
    actionHeader:SetPoint("TOPLEFT", actionSection, "TOPLEFT", 8, -8)
    actionHeader:SetText("ACTION")
    actionHeader:SetTextColor(ar, ag, ab, 1)

    -- Get action metadata
    local actionId = rule.action and rule.action.id
    local actionMeta = actionId and addon.Rules and addon.Rules:GetActionMetadata(actionId)
    local widget = actionMeta and actionMeta.widget or "checkbox"
    local currentValue = rule.action and rule.action.value

    -- Render appropriate control
    if actionId and actionMeta then
        if widget == "checkbox" then
            -- TUI Toggle-style control
            local toggle = Controls:CreateToggle({
                parent = actionSection,
                label = actionMeta.path and actionMeta.path[#actionMeta.path] or "Enabled",
                get = function() return currentValue and true or false end,
                set = function(val)
                    if addon.Rules and addon.Rules.SetRuleActionValue then
                        addon.Rules:SetRuleActionValue(rule.id, val)
                    end
                end,
            })
            toggle:SetPoint("TOPLEFT", actionHeader, "BOTTOMLEFT", 0, -12)
            toggle:SetWidth(300)
            card._actionToggle = toggle

        elseif widget == "slider" then
            local uiMeta = actionMeta.uiMeta or {}
            local slider = Controls:CreateSlider({
                parent = actionSection,
                label = actionMeta.path and actionMeta.path[#actionMeta.path] or "Value",
                min = uiMeta.min or 0,
                max = uiMeta.max or 100,
                step = uiMeta.step or 1,
                get = function() return tonumber(currentValue) or uiMeta.min or 0 end,
                set = function(val)
                    if addon.Rules and addon.Rules.SetRuleActionValue then
                        addon.Rules:SetRuleActionValue(rule.id, val)
                    end
                end,
                width = 200,
            })
            slider:SetPoint("TOPLEFT", actionHeader, "BOTTOMLEFT", 0, -12)
            slider:SetWidth(400)
            card._actionSlider = slider

        elseif widget == "dropdown" then
            local uiMeta = actionMeta.uiMeta or {}
            local values = uiMeta.values or {}
            local selector = Controls:CreateSelector({
                parent = actionSection,
                label = actionMeta.path and actionMeta.path[#actionMeta.path] or "Option",
                values = values,
                get = function() return currentValue end,
                set = function(val)
                    if addon.Rules and addon.Rules.SetRuleActionValue then
                        addon.Rules:SetRuleActionValue(rule.id, val)
                    end
                end,
                width = 200,
            })
            selector:SetPoint("TOPLEFT", actionHeader, "BOTTOMLEFT", 0, -12)
            selector:SetWidth(400)
            card._actionSelector = selector

        elseif widget == "color" then
            local colorPicker = Controls:CreateColorPicker({
                parent = actionSection,
                label = actionMeta.path and actionMeta.path[#actionMeta.path] or "Color",
                get = function()
                    local c = currentValue
                    if type(c) == "table" then
                        return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                    end
                    return 1, 1, 1, 1
                end,
                set = function(r, g, b, a)
                    if addon.Rules and addon.Rules.SetRuleActionValue then
                        addon.Rules:SetRuleActionValue(rule.id, { r, g, b, a })
                    end
                end,
                hasAlpha = true,
            })
            colorPicker:SetPoint("TOPLEFT", actionHeader, "BOTTOMLEFT", 0, -12)
            colorPicker:SetWidth(400)
            card._actionColor = colorPicker
        end
    else
        -- No action selected placeholder
        local placeholder = actionSection:CreateFontString(nil, "OVERLAY")
        placeholder:SetFont(fontPath, 11, "")
        placeholder:SetPoint("TOPLEFT", actionHeader, "BOTTOMLEFT", 0, -12)
        placeholder:SetText("Select a target setting above to configure the action value.")
        placeholder:SetTextColor(dimR, dimG, dimB, 1)
    end
end

--------------------------------------------------------------------------------
-- Rules: Create TUI-styled rule card
--------------------------------------------------------------------------------

local function CreateRulesCard(parent, rule, refreshCallback)
    local state = Rules._state
    local isEditing = state.editingRules[rule.id]

    -- Get theme colors
    local ar, ag, ab = Theme:GetAccentColor()
    local bgR, bgG, bgB, bgA = Theme:GetCollapsibleBgColor()
    local dimR, dimG, dimB = Theme:GetDimTextColor()

    -- Card container with TUI styling (gray background within border)
    local card = CreateFrame("Frame", nil, parent)
    card:SetHeight(isEditing and RULES_CARD_HEIGHT_EDIT or RULES_CARD_HEIGHT_DISPLAY)

    -- Gray background (like collapsible section headers per HOLDING3.md)
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(bgR, bgG, bgB, bgA)
    card._bg = bg

    -- Border
    local borderAlpha = 0.6
    local borders = {}
    local function createBorder(side)
        local tex = card:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(ar, ag, ab, borderAlpha)
        if side == "TOP" then
            tex:SetHeight(1)
            tex:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
            tex:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
        elseif side == "BOTTOM" then
            tex:SetHeight(1)
            tex:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
        elseif side == "LEFT" then
            tex:SetWidth(1)
            tex:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
        elseif side == "RIGHT" then
            tex:SetWidth(1)
            tex:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
        end
        borders[side] = tex
    end
    createBorder("TOP")
    createBorder("BOTTOM")
    createBorder("LEFT")
    createBorder("RIGHT")
    card._borders = borders

    -- Theme subscription
    local subscribeKey = "RulesCard_" .. (rule.id or tostring(card))
    Theme:Subscribe(subscribeKey, function(r, g, b)
        for _, tex in pairs(borders) do
            tex:SetColorTexture(r, g, b, borderAlpha)
        end
    end)
    card._subscribeKey = subscribeKey

    card.Cleanup = function(self)
        if self._subscribeKey then
            Theme:Unsubscribe(self._subscribeKey)
        end
        -- Clean up spec badges
        if self._specBadges then
            for _, badge in ipairs(self._specBadges) do
                badge:Hide()
                badge:SetParent(nil)
            end
        end
    end

    -- === INDEX BADGE (outside card, on the left) ===
    local indexBadge = CreateFrame("Frame", nil, card)
    indexBadge:SetSize(RULES_INDEX_BADGE_SIZE, RULES_INDEX_BADGE_SIZE)
    indexBadge:SetPoint("TOPRIGHT", card, "TOPLEFT", -10, -8)

    local indexBg = indexBadge:CreateTexture(nil, "BACKGROUND")
    indexBg:SetAllPoints()
    indexBg:SetColorTexture(ar, ag, ab, 1)
    indexBadge._bg = indexBg

    local indexText = indexBadge:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("LABEL")
    indexText:SetFont(fontPath, 12, "")
    indexText:SetPoint("CENTER")
    indexText:SetText(tostring(rule.displayIndex or "?"))
    indexText:SetTextColor(0.05, 0.05, 0.05, 1)  -- Dark text for contrast
    indexBadge._text = indexText
    card._indexBadge = indexBadge

    if isEditing then
        -- === EDIT MODE ===
        RenderRulesCardEditMode(card, rule, refreshCallback, ar, ag, ab)
    else
        -- === DISPLAY MODE ===
        RenderRulesCardDisplayMode(card, rule, refreshCallback, ar, ag, ab)
    end

    return card
end

--------------------------------------------------------------------------------
-- Rules: Divider between cards
--------------------------------------------------------------------------------

local function CreateRulesDivider(parent)
    local ar, ag, ab = Theme:GetAccentColor()

    local divider = CreateFrame("Frame", nil, parent)
    divider:SetHeight(RULES_DIVIDER_HEIGHT)

    -- Left line
    local leftLine = divider:CreateTexture(nil, "ARTWORK")
    leftLine:SetHeight(1)
    leftLine:SetPoint("LEFT", divider, "LEFT", RULES_CARD_LEFT_MARGIN, 0)
    leftLine:SetPoint("RIGHT", divider, "CENTER", -16, 0)
    leftLine:SetColorTexture(ar, ag, ab, 0.3)
    divider._leftLine = leftLine

    -- Right line
    local rightLine = divider:CreateTexture(nil, "ARTWORK")
    rightLine:SetHeight(1)
    rightLine:SetPoint("LEFT", divider, "CENTER", 16, 0)
    rightLine:SetPoint("RIGHT", divider, "RIGHT", -8, 0)
    rightLine:SetColorTexture(ar, ag, ab, 0.3)
    divider._rightLine = rightLine

    -- Center diamond ornament
    local ornament = divider:CreateTexture(nil, "OVERLAY")
    ornament:SetSize(10, 10)
    ornament:SetPoint("CENTER", divider, "CENTER", 0, 0)
    ornament:SetTexture("Interface\\Buttons\\WHITE8x8")
    ornament:SetVertexColor(ar, ag, ab, 0.6)
    ornament:SetRotation(math.rad(45))
    divider._ornament = ornament

    -- Theme subscription
    local subscribeKey = "RulesDivider_" .. tostring(divider)
    Theme:Subscribe(subscribeKey, function(r, g, b)
        leftLine:SetColorTexture(r, g, b, 0.3)
        rightLine:SetColorTexture(r, g, b, 0.3)
        ornament:SetVertexColor(r, g, b, 0.6)
    end)
    divider._subscribeKey = subscribeKey

    divider.Cleanup = function(self)
        if self._subscribeKey then
            Theme:Unsubscribe(self._subscribeKey)
        end
    end

    return divider
end

--------------------------------------------------------------------------------
-- Rules: Main renderer
--------------------------------------------------------------------------------

function Rules.Render(panel, scrollContent)
    panel._rulesState = Rules._state
    panel:ClearContent()

    -- Clean up previous Rules UI controls
    local state = Rules._state
    if state.currentControls then
        for _, control in ipairs(state.currentControls) do
            if control.Cleanup then
                control:Cleanup()
            end
            if control.Hide then
                control:Hide()
            end
            if control.SetParent then
                control:SetParent(nil)
            end
        end
    end
    state.currentControls = {}

    local ar, ag, ab = Theme:GetAccentColor()
    local fontPath = Theme:GetFont("VALUE")

    -- Refresh callback
    local function refreshRules()
        Rules.Render(panel, scrollContent)
    end

    local yOffset = -8

    -- Add Rule button
    local addBtn = Controls:CreateButton({
        parent = scrollContent,
        text = "Add Rule",
        width = 200,
        height = 36,
        onClick = function()
            if addon.Rules and addon.Rules.CreateRule then
                local newRule = addon.Rules:CreateRule()
                if newRule and newRule.id then
                    state.editingRules[newRule.id] = true
                end
                refreshRules()
            end
        end,
    })
    addBtn:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    table.insert(state.currentControls, addBtn)
    yOffset = yOffset - RULES_ADD_BUTTON_HEIGHT

    -- Get rules
    local rules = addon.Rules and addon.Rules:GetRules() or {}

    if #rules == 0 then
        -- Empty state
        local emptyFrame = CreateFrame("Frame", nil, scrollContent)
        emptyFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", RULES_CARD_LEFT_MARGIN, yOffset - 20)
        emptyFrame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -8, yOffset - 20)
        emptyFrame:SetHeight(40)

        local emptyText = emptyFrame:CreateFontString(nil, "OVERLAY")
        emptyText:SetFont(fontPath, 12, "")
        emptyText:SetAllPoints()
        emptyText:SetText("No rules configured. Click 'Add Rule' to create your first automation.")
        emptyText:SetTextColor(0.6, 0.6, 0.6, 1)
        emptyText:SetJustifyH("CENTER")

        table.insert(state.currentControls, emptyFrame)
        yOffset = yOffset - RULES_EMPTY_STATE_HEIGHT
    else
        -- Render each rule
        for index, rule in ipairs(rules) do
            rule.displayIndex = index

            local card = CreateRulesCard(scrollContent, rule, refreshRules)
            card:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", RULES_CARD_LEFT_MARGIN, yOffset)
            card:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -8, yOffset)
            yOffset = yOffset - card:GetHeight()

            -- Track for cleanup
            table.insert(state.currentControls, card)

            -- Divider between cards (not after last)
            if index < #rules then
                local divider = CreateRulesDivider(scrollContent)
                divider:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
                divider:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, yOffset)
                yOffset = yOffset - RULES_DIVIDER_HEIGHT
                table.insert(state.currentControls, divider)
            end
        end
    end

    -- Set scroll content height
    local totalHeight = math.abs(yOffset) + 20
    scrollContent:SetHeight(totalHeight)
end

addon.UI.SettingsPanel:RegisterRenderer("profilesRules", function(panel, scrollContent)
    Rules.Render(panel, scrollContent)
end)

return Rules
