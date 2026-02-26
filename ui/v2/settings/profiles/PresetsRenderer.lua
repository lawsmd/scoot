-- PresetsRenderer.lua - Profiles Presets settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Profiles = addon.UI.Settings.Profiles or {}
addon.UI.Settings.Profiles.Presets = {}

local Presets = addon.UI.Settings.Profiles.Presets
local SettingsBuilder = addon.UI.SettingsBuilder
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls

-- State management for this renderer
Presets._state = {
    currentControls = {},
    selectedIndex = 1,
}

function Presets.Render(panel, scrollContent)
    panel._presetsState = Presets._state
    panel:ClearContent()

    -- Clean up previous controls
    local state = Presets._state
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
    local dimR, dimG, dimB = Theme:GetDimTextColor()
    local fontPath = Theme:GetFont("VALUE")
    local fontPathMed = Theme:GetFont("LABEL")
    local fontPathBold = Theme:GetFont("HEADER")

    -- Constants
    local CONTENT_PADDING = 8
    local HERO_WIDTH = 560
    local HERO_HEIGHT = 315
    local COLUMN_WIDTH = 240
    local COLUMN_OUTER_MARGIN = 40
    local BUTTON_WIDTH = 280
    local BUTTON_HEIGHT = 36

    -- Get preset list
    local function getPresetList()
        if not addon.Presets or not addon.Presets.GetList then
            return {}
        end
        return addon.Presets:GetList()
    end

    local presets = getPresetList()

    -- Clamp selected index
    if state.selectedIndex < 1 then state.selectedIndex = 1 end
    if state.selectedIndex > #presets then state.selectedIndex = math.max(1, #presets) end

    -- Refresh callback
    local function refreshPresets()
        Presets.Render(panel, scrollContent)
    end

    local yOffset = -CONTENT_PADDING

    ---------------------------------------------------------------------------
    -- Empty State
    ---------------------------------------------------------------------------
    if #presets == 0 then
        local emptyFrame = CreateFrame("Frame", nil, scrollContent)
        emptyFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, yOffset - 40)
        emptyFrame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, yOffset - 40)
        emptyFrame:SetHeight(100)

        -- Terminal-style empty message
        local emptyText = emptyFrame:CreateFontString(nil, "OVERLAY")
        emptyText:SetFont(fontPath, 14, "")
        emptyText:SetPoint("CENTER", emptyFrame, "CENTER", 0, 0)
        emptyText:SetText("[ No presets available ]\n\nPreset collections are coming soon.\nFor now, use Edit Mode to swap between\nBlizzard's Modern and Classic presets.")
        emptyText:SetTextColor(dimR, dimG, dimB, 1)
        emptyText:SetJustifyH("CENTER")

        table.insert(state.currentControls, emptyFrame)
        scrollContent:SetHeight(200)
        return
    end

    ---------------------------------------------------------------------------
    -- Preset Selector (horizontal: label on left, dropdown on right)
    ---------------------------------------------------------------------------
    local selectorRow = CreateFrame("Frame", nil, scrollContent)
    selectorRow:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    selectorRow:SetSize(400, 32)
    table.insert(state.currentControls, selectorRow)

    local selectorLabel = selectorRow:CreateFontString(nil, "OVERLAY")
    selectorLabel:SetFont(fontPathMed, 14, "")
    selectorLabel:SetPoint("LEFT", selectorRow, "LEFT", 0, 0)
    selectorLabel:SetText("Select a preset:")
    selectorLabel:SetTextColor(ar, ag, ab, 1)

    -- Build dropdown values
    local dropdownValues = {}
    local dropdownOrder = {}
    for i, preset in ipairs(presets) do
        local key = tostring(i)
        dropdownValues[key] = preset.name or preset.id or ("Preset " .. i)
        table.insert(dropdownOrder, key)
    end

    local presetDropdown = Controls:CreateDropdown({
        parent = selectorRow,
        values = dropdownValues,
        order = dropdownOrder,
        get = function()
            return tostring(state.selectedIndex)
        end,
        set = function(key)
            state.selectedIndex = tonumber(key) or 1
            refreshPresets()
        end,
        placeholder = "Select a preset...",
        width = 240,
        height = 26,
        fontSize = 12,
    })
    presetDropdown:SetPoint("LEFT", selectorLabel, "RIGHT", 12, 0)
    table.insert(state.currentControls, presetDropdown)
    yOffset = yOffset - 40

    -- Get current preset
    local currentPreset = presets[state.selectedIndex]
    if not currentPreset then
        scrollContent:SetHeight(100)
        return
    end

    ---------------------------------------------------------------------------
    -- Hero Image (with TUI-styled border)
    ---------------------------------------------------------------------------
    local heroContainer = CreateFrame("Frame", nil, scrollContent)
    heroContainer:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    heroContainer:SetSize(HERO_WIDTH + 6, HERO_HEIGHT + 6)

    -- Border around hero image
    local borderTop = heroContainer:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT", heroContainer, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", heroContainer, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(2)
    borderTop:SetColorTexture(ar, ag, ab, 0.6)

    local borderBottom = heroContainer:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT", heroContainer, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", heroContainer, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(2)
    borderBottom:SetColorTexture(ar, ag, ab, 0.6)

    local borderLeft = heroContainer:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT", heroContainer, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", heroContainer, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(2)
    borderLeft:SetColorTexture(ar, ag, ab, 0.6)

    local borderRight = heroContainer:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT", heroContainer, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", heroContainer, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(2)
    borderRight:SetColorTexture(ar, ag, ab, 0.6)

    -- Hero image texture
    local heroTexture = heroContainer:CreateTexture(nil, "ARTWORK")
    heroTexture:SetPoint("TOPLEFT", heroContainer, "TOPLEFT", 3, -3)
    heroTexture:SetPoint("BOTTOMRIGHT", heroContainer, "BOTTOMRIGHT", -3, 3)
    heroTexture:SetTexture(currentPreset.previewTexture or "Interface\\AddOns\\Scoot\\media\\presets\\Scoot")

    -- "Coming Soon" overlay if applicable
    if currentPreset.comingSoon then
        local overlay = heroContainer:CreateTexture(nil, "OVERLAY")
        overlay:SetAllPoints(heroTexture)
        overlay:SetColorTexture(0, 0, 0, 0.7)

        local comingSoonText = heroContainer:CreateFontString(nil, "OVERLAY")
        comingSoonText:SetFont(fontPathBold, 24, "")
        comingSoonText:SetPoint("CENTER", heroContainer, "CENTER", 0, 0)
        comingSoonText:SetText("COMING SOON")
        comingSoonText:SetTextColor(ar, ag, ab, 1)
    end

    table.insert(state.currentControls, heroContainer)
    yOffset = yOffset - (HERO_HEIGHT + 6) - 20

    ---------------------------------------------------------------------------
    -- Two-Column Info Section
    ---------------------------------------------------------------------------
    local columnsContainer = CreateFrame("Frame", nil, scrollContent)
    columnsContainer:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    columnsContainer:SetSize(HERO_WIDTH + (COLUMN_OUTER_MARGIN * 2), 120)
    table.insert(state.currentControls, columnsContainer)

    -- Helper to format bullet list
    local function formatBulletList(items)
        if type(items) ~= "table" or #items == 0 then
            return "> (none specified)"
        end
        local lines = {}
        for _, item in ipairs(items) do
            table.insert(lines, "> " .. tostring(item))
        end
        return table.concat(lines, "\n")
    end

    -- Left column: "Designed for..."
    local leftHeader = columnsContainer:CreateFontString(nil, "OVERLAY")
    leftHeader:SetFont(fontPathMed, 14, "")
    leftHeader:SetPoint("TOPLEFT", columnsContainer, "TOPLEFT", COLUMN_OUTER_MARGIN, 0)
    leftHeader:SetText("Designed for...")
    leftHeader:SetTextColor(ar, ag, ab, 1)

    local leftList = columnsContainer:CreateFontString(nil, "OVERLAY")
    leftList:SetFont(fontPath, 12, "")
    leftList:SetPoint("TOPLEFT", leftHeader, "BOTTOMLEFT", 0, -8)
    leftList:SetWidth(COLUMN_WIDTH)
    leftList:SetJustifyH("LEFT")
    leftList:SetJustifyV("TOP")
    leftList:SetText(formatBulletList(currentPreset.designedFor))
    leftList:SetTextColor(1, 1, 1, 0.9)
    leftList:SetSpacing(4)

    -- Right column: "Author also recommends..."
    local rightHeader = columnsContainer:CreateFontString(nil, "OVERLAY")
    rightHeader:SetFont(fontPathMed, 14, "")
    rightHeader:SetPoint("TOPLEFT", columnsContainer, "TOP", 40, 0)
    rightHeader:SetText("Author also recommends...")
    rightHeader:SetTextColor(ar, ag, ab, 1)

    local rightList = columnsContainer:CreateFontString(nil, "OVERLAY")
    rightList:SetFont(fontPath, 12, "")
    rightList:SetPoint("TOPLEFT", rightHeader, "BOTTOMLEFT", 0, -8)
    rightList:SetWidth(COLUMN_WIDTH)
    rightList:SetJustifyH("LEFT")
    rightList:SetJustifyV("TOP")
    rightList:SetText(formatBulletList(currentPreset.recommends))
    rightList:SetTextColor(1, 1, 1, 0.9)
    rightList:SetSpacing(4)

    -- Calculate column height based on content
    C_Timer.After(0, function()
        if leftList and rightList and columnsContainer then
            local leftH = leftList:GetStringHeight() or 60
            local rightH = rightList:GetStringHeight() or 60
            local maxH = math.max(leftH, rightH) + 30
            columnsContainer:SetHeight(maxH)
        end
    end)

    yOffset = yOffset - 140

    ---------------------------------------------------------------------------
    -- Apply Button
    ---------------------------------------------------------------------------
    -- Determine if preset is actionable
    local canApplyPayload = addon.Presets and addon.Presets.IsPayloadReady and addon.Presets:IsPayloadReady(currentPreset)
    local depsOk, depsErr = true, nil
    if addon.Presets and addon.Presets.CheckDependencies then
        depsOk, depsErr = addon.Presets:CheckDependencies(currentPreset)
    end
    local actionable = canApplyPayload and depsOk and not currentPreset.comingSoon

    local disabledReason
    if not canApplyPayload then
        disabledReason = "Preset payload pending."
    elseif not depsOk then
        disabledReason = depsErr or "Dependencies not met."
    elseif currentPreset.comingSoon then
        disabledReason = "Preset not yet published."
    end

    local applyBtn = Controls:CreateButton({
        parent = scrollContent,
        text = "Apply this preset",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            if not actionable then return end
            -- Use the core Presets module's ApplyPresetFromUI method
            if addon.Presets and addon.Presets.ApplyPresetFromUI then
                addon.Presets:ApplyPresetFromUI(currentPreset)
            end
        end,
    })
    applyBtn:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    applyBtn:SetEnabled(actionable)
    if not actionable then
        applyBtn:SetAlpha(0.5)
    end
    table.insert(state.currentControls, applyBtn)

    -- Tooltip for disabled state
    if not actionable and disabledReason then
        applyBtn:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText(disabledReason, 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        applyBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    yOffset = yOffset - BUTTON_HEIGHT - 24

    ---------------------------------------------------------------------------
    -- Additional Info (optional notes)
    ---------------------------------------------------------------------------
    if currentPreset.notes and currentPreset.notes ~= "" then
        local notesFrame = CreateFrame("Frame", nil, scrollContent)
        notesFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING + 40, yOffset)
        notesFrame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING - 40, yOffset)
        notesFrame:SetHeight(60)

        local notesText = notesFrame:CreateFontString(nil, "OVERLAY")
        notesText:SetFont(fontPath, 11, "")
        notesText:SetAllPoints()
        notesText:SetText(currentPreset.notes)
        notesText:SetTextColor(dimR, dimG, dimB, 1)
        notesText:SetJustifyH("CENTER")
        notesText:SetWordWrap(true)

        table.insert(state.currentControls, notesFrame)
        yOffset = yOffset - 70
    end

    ---------------------------------------------------------------------------
    -- Set scroll content height
    ---------------------------------------------------------------------------
    local totalHeight = math.abs(yOffset) + 40
    scrollContent:SetHeight(totalHeight)
end

addon.UI.SettingsPanel:RegisterRenderer("profilesPresets", function(panel, scrollContent)
    Presets.Render(panel, scrollContent)
end)

return Presets
