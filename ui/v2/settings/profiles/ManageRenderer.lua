-- ManageRenderer.lua - Profiles Management settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Profiles = addon.UI.Settings.Profiles or {}
addon.UI.Settings.Profiles.Manage = {}

local Manage = addon.UI.Settings.Profiles.Manage
local SettingsBuilder = addon.UI.SettingsBuilder
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls

-- State management for this renderer
Manage._state = {
    currentControls = {},
}

function Manage.Render(panel, scrollContent)
    panel._profilesManageState = Manage._state
    panel:ClearContent()

    -- Clean up previous Profiles Manage controls
    local state = Manage._state
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

    -- Constants for this page
    local DROPDOWN_SCALE = 1.2
    local BUTTON_WIDTH = 140
    local BUTTON_HEIGHT = 32
    local BUTTON_GAP = 16
    local SPEC_ICON_SIZE = 28
    local CONTENT_PADDING = 8

    -- Refresh callback
    local function refreshProfilesManage()
        Manage.Render(panel, scrollContent)
    end

    -- Helper: Get active profile key
    local function getActiveProfileKey()
        if addon.Profiles and addon.Profiles.GetActiveProfile then
            return addon.Profiles:GetActiveProfile()
        end
        if addon.db and addon.db.GetCurrentProfile then
            return addon.db:GetCurrentProfile()
        end
    end

    -- Helper: Build layout menu entries
    local function buildLayoutEntries()
        if not addon.Profiles or not addon.Profiles.GetLayoutMenuEntries then
            return {}
        end
        return addon.Profiles:GetLayoutMenuEntries()
    end

    -- Track y offset for manual layout
    local yOffset = -CONTENT_PADDING

    ---------------------------------------------------------------------------
    -- Info Text Section
    ---------------------------------------------------------------------------
    local infoFrame = CreateFrame("Frame", nil, scrollContent)
    infoFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING + 8, yOffset)
    infoFrame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING - 8, yOffset)

    local infoText = infoFrame:CreateFontString(nil, "OVERLAY")
    infoText:SetFont(fontPath, 13, "")
    infoText:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 0, 0)
    infoText:SetPoint("TOPRIGHT", infoFrame, "TOPRIGHT", 0, 0)
    infoText:SetText("Scoot profiles stay synchronized with Edit Mode layouts. Switch layouts here or via Edit Mode and Scoot will keep them in sync.")
    infoText:SetTextColor(dimR, dimG, dimB, 1)
    infoText:SetJustifyH("LEFT")
    infoText:SetWordWrap(true)

    -- Calculate text height after layout
    C_Timer.After(0, function()
        if infoText and infoFrame then
            local h = infoText:GetStringHeight() or 40
            infoFrame:SetHeight(h + 8)
        end
    end)
    infoFrame:SetHeight(50)
    table.insert(state.currentControls, infoFrame)
    yOffset = yOffset - 60

    ---------------------------------------------------------------------------
    -- Active Layout Dropdown (centered, larger)
    ---------------------------------------------------------------------------
    local activeLayoutLabel = scrollContent:CreateFontString(nil, "OVERLAY")
    activeLayoutLabel:SetFont(fontPathMed, 18, "")
    activeLayoutLabel:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    activeLayoutLabel:SetText("Active Layout")
    activeLayoutLabel:SetTextColor(ar, ag, ab, 1)
    table.insert(state.currentControls, activeLayoutLabel)
    yOffset = yOffset - 24

    -- Build values and order for dropdown
    local entries = buildLayoutEntries()
    local dropdownValues = {}
    local dropdownOrder = {}
    for _, entry in ipairs(entries) do
        dropdownValues[entry.key] = entry.text
        table.insert(dropdownOrder, entry.key)
    end

    local activeDropdown = Controls:CreateDropdown({
        parent = scrollContent,
        values = dropdownValues,
        order = dropdownOrder,
        get = function()
            return getActiveProfileKey()
        end,
        set = function(key)
            local entry = nil
            for _, e in ipairs(entries) do
                if e.key == key then
                    entry = e
                    break
                end
            end
            if entry and entry.preset then
                -- Preset selected - need to clone
                local currentKey = getActiveProfileKey()
                addon.Profiles:PromptClonePreset(key, nil, entry.text, currentKey)
                return
            end
            if addon.Profiles and addon.Profiles.SwitchToProfile then
                addon.Profiles:SwitchToProfile(key, { reason = "ManageProfilesDropdown" })
            end
            -- Refresh after switch
            C_Timer.After(0.1, refreshProfilesManage)
        end,
        placeholder = "Select a layout...",
        width = 240,
        height = 28,
        fontSize = 13,
    })
    activeDropdown:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    activeDropdown:SetScale(DROPDOWN_SCALE)
    table.insert(state.currentControls, activeDropdown)
    yOffset = yOffset - (34 * DROPDOWN_SCALE) - 28

    -- Store reference for button state updates
    state.activeDropdown = activeDropdown

    ---------------------------------------------------------------------------
    -- Action Buttons Row (Create, Rename, Copy)
    ---------------------------------------------------------------------------
    local totalButtonsWidth = (BUTTON_WIDTH * 3) + (BUTTON_GAP * 2)
    local startX = -totalButtonsWidth / 2

    -- Update button states helper
    local function updateButtonStates()
        local current = getActiveProfileKey()
        local isPreset = current and addon.Profiles and addon.Profiles:IsPreset(current)
        if state.renameBtn then
            state.renameBtn:SetEnabled(current and not isPreset)
        end
        if state.copyBtn then
            state.copyBtn:SetEnabled(not not current)
        end
    end

    -- Create button
    local createBtn = Controls:CreateButton({
        parent = scrollContent,
        text = "Create",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            addon.Profiles:PromptCreateLayout(nil)
            C_Timer.After(0.1, refreshProfilesManage)
        end,
    })
    createBtn:SetPoint("TOP", scrollContent, "TOP", startX + (BUTTON_WIDTH / 2), yOffset)
    table.insert(state.currentControls, createBtn)
    state.createBtn = createBtn

    -- Rename button
    local renameBtn = Controls:CreateButton({
        parent = scrollContent,
        text = "Rename",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            local current = getActiveProfileKey()
            if current then
                addon.Profiles:PromptRenameLayout(current, nil)
                C_Timer.After(0.1, refreshProfilesManage)
            end
        end,
    })
    renameBtn:SetPoint("LEFT", createBtn, "RIGHT", BUTTON_GAP, 0)
    table.insert(state.currentControls, renameBtn)
    state.renameBtn = renameBtn

    -- Copy button
    local copyBtn = Controls:CreateButton({
        parent = scrollContent,
        text = "Copy",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            local current = getActiveProfileKey()
            if not current then return end
            if addon.Profiles and addon.Profiles:IsPreset(current) then
                addon.Profiles:PromptClonePreset(current, nil, addon.Profiles:GetLayoutDisplayText(current), current)
            else
                addon.Profiles:PromptCopyLayout(current, nil)
            end
            C_Timer.After(0.1, refreshProfilesManage)
        end,
    })
    copyBtn:SetPoint("LEFT", renameBtn, "RIGHT", BUTTON_GAP, 0)
    table.insert(state.currentControls, copyBtn)
    state.copyBtn = copyBtn

    -- Update button states
    updateButtonStates()
    yOffset = yOffset - BUTTON_HEIGHT - 24

    ---------------------------------------------------------------------------
    -- Delete a Profile (Collapsible Section)
    ---------------------------------------------------------------------------
    local deleteSection = Controls:CreateCollapsibleSection({
        parent = scrollContent,
        title = "Delete a Profile",
        componentId = "profilesManage",
        sectionKey = "deleteProfile",
        defaultExpanded = false,
        onToggle = function()
            C_Timer.After(0, refreshProfilesManage)
        end,
    })
    deleteSection:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, yOffset)
    deleteSection:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, yOffset)
    table.insert(state.currentControls, deleteSection)

    -- Build delete dropdown content
    local deleteContent = deleteSection:GetContentFrame()

    -- Get deletable profiles (exclude current and presets)
    local function getDeletableProfiles()
        local deletable = {}
        local currentProfile = getActiveProfileKey()
        for _, entry in ipairs(entries) do
            if entry.key ~= currentProfile and not entry.preset then
                table.insert(deletable, entry)
            end
        end
        return deletable
    end

    local deletable = getDeletableProfiles()
    local deleteValues = {}
    local deleteOrder = {}
    for _, entry in ipairs(deletable) do
        deleteValues[entry.key] = entry.text
        table.insert(deleteOrder, entry.key)
    end

    local deleteDropdown = Controls:CreateDropdown({
        parent = deleteContent,
        values = deleteValues,
        order = deleteOrder,
        set = function(key)
            -- Confirm deletion
            addon.Profiles:ConfirmDeleteLayout(key, nil)
            C_Timer.After(0.2, refreshProfilesManage)
        end,
        placeholder = #deletable > 0 and "Select a profile to delete..." or "No deletable profiles",
        width = 280,
        height = 26,
        fontSize = 12,
    })
    deleteDropdown:SetPoint("TOP", deleteContent, "TOP", 0, -12)
    table.insert(state.currentControls, deleteDropdown)

    -- Set content height
    deleteSection:SetContentHeight(60)

    -- Get section height and update offset
    local deleteSectionHeight = deleteSection:GetHeight()
    yOffset = yOffset - deleteSectionHeight - 16

    ---------------------------------------------------------------------------
    -- Spec Profiles (Collapsible Section)
    ---------------------------------------------------------------------------
    local specSection = Controls:CreateCollapsibleSection({
        parent = scrollContent,
        title = "Spec Profiles",
        componentId = "profilesManage",
        sectionKey = "specProfiles",
        defaultExpanded = false,
        onToggle = function()
            C_Timer.After(0, refreshProfilesManage)
        end,
    })
    specSection:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, yOffset)
    specSection:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, yOffset)
    table.insert(state.currentControls, specSection)

    local specContent = specSection:GetContentFrame()

    -- Enable Spec Profiles toggle
    local specEnabled = addon.Profiles and addon.Profiles.IsSpecProfilesEnabled and addon.Profiles:IsSpecProfilesEnabled() or false

    local enableToggle = Controls:CreateToggle({
        parent = specContent,
        label = "Enable Spec Profiles",
        description = "Automatically switch profiles when you change specializations.",
        get = function()
            return addon.Profiles and addon.Profiles:IsSpecProfilesEnabled() or false
        end,
        set = function(value)
            local wasEnabled = addon.Profiles and addon.Profiles:IsSpecProfilesEnabled()
            if addon.Profiles and addon.Profiles.SetSpecProfilesEnabled then
                addon.Profiles:SetSpecProfilesEnabled(value)
            end
            -- Seed assignments when first enabling
            if value and not wasEnabled then
                local current = getActiveProfileKey()
                if current and addon.Profiles and addon.Profiles.SetSpecAssignment then
                    local specs = (addon.Profiles.GetSpecOptions and addon.Profiles:GetSpecOptions()) or {}
                    for _, s in ipairs(specs) do
                        if s and s.specID then
                            addon.Profiles:SetSpecAssignment(s.specID, current)
                        end
                    end
                end
            end
            if value and addon.Profiles and addon.Profiles.OnPlayerSpecChanged then
                addon.Profiles:OnPlayerSpecChanged()
            end
            -- Refresh to show/hide spec rows
            C_Timer.After(0.05, refreshProfilesManage)
        end,
    })
    enableToggle:SetPoint("TOPLEFT", specContent, "TOPLEFT", 0, 0)
    enableToggle:SetPoint("TOPRIGHT", specContent, "TOPRIGHT", 0, 0)
    table.insert(state.currentControls, enableToggle)

    local specContentHeight = enableToggle:GetHeight() + 8

    -- Spec rows (only if enabled)
    if specEnabled then
        local specOptions = (addon.Profiles and addon.Profiles.GetSpecOptions and addon.Profiles:GetSpecOptions()) or {}
        local specYOffset = -enableToggle:GetHeight() - 16

        for _, spec in ipairs(specOptions) do
            -- Spec row frame
            local specRow = CreateFrame("Frame", nil, specContent)
            specRow:SetPoint("TOPLEFT", specContent, "TOPLEFT", 8, specYOffset)
            specRow:SetPoint("TOPRIGHT", specContent, "TOPRIGHT", -8, specYOffset)
            specRow:SetHeight(40)

            -- Spec icon
            local specIcon = specRow:CreateTexture(nil, "ARTWORK")
            specIcon:SetSize(SPEC_ICON_SIZE, SPEC_ICON_SIZE)
            specIcon:SetPoint("LEFT", specRow, "LEFT", 0, 0)
            if spec.icon then
                specIcon:SetTexture(spec.icon)
            end

            -- Spec name
            local specName = specRow:CreateFontString(nil, "OVERLAY")
            specName:SetFont(fontPath, 13, "")
            specName:SetPoint("LEFT", specIcon, "RIGHT", 10, 0)
            specName:SetText(spec.name or ("Spec " .. tostring(spec.specIndex)))
            specName:SetTextColor(1, 1, 1, 1)
            specName:SetWidth(120)
            specName:SetJustifyH("LEFT")

            -- Spec dropdown (profile assignment)
            local assigned = addon.Profiles and addon.Profiles.GetSpecAssignment and addon.Profiles:GetSpecAssignment(spec.specID) or nil

            local specDropdown = Controls:CreateDropdown({
                parent = specRow,
                values = dropdownValues,
                order = dropdownOrder,
                get = function()
                    return addon.Profiles and addon.Profiles:GetSpecAssignment(spec.specID) or getActiveProfileKey()
                end,
                set = function(key)
                    if addon.Profiles and addon.Profiles.SetSpecAssignment then
                        addon.Profiles:SetSpecAssignment(spec.specID, key)
                    end
                    -- Trigger spec change if applicable
                    if addon.Profiles and addon.Profiles:IsSpecProfilesEnabled() then
                        if addon.Profiles.OnPlayerSpecChanged then
                            addon.Profiles:OnPlayerSpecChanged()
                        end
                    end
                end,
                placeholder = "Select a layout...",
                width = 200,
                height = 24,
                fontSize = 11,
            })
            specDropdown:SetPoint("LEFT", specName, "RIGHT", 16, 0)

            table.insert(state.currentControls, specRow)
            table.insert(state.currentControls, specDropdown)

            specYOffset = specYOffset - 44
            specContentHeight = specContentHeight + 44
        end
    end

    -- Set content height for spec section
    specSection:SetContentHeight(specContentHeight + 16)

    local specSectionHeight = specSection:GetHeight()
    yOffset = yOffset - specSectionHeight - 24

    ---------------------------------------------------------------------------
    -- Warning Notice (bottom)
    ---------------------------------------------------------------------------
    local warningFrame = CreateFrame("Frame", nil, scrollContent)
    warningFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, yOffset)
    warningFrame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, yOffset)
    warningFrame:SetHeight(80)

    -- Divider line above warning
    local divider = warningFrame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", warningFrame, "TOPLEFT", 0, 0)
    divider:SetPoint("TOPRIGHT", warningFrame, "TOPRIGHT", 0, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(ar, ag, ab, 0.3)

    -- Warning text
    local warningText = warningFrame:CreateFontString(nil, "OVERLAY")
    warningText:SetFont(fontPath, 12, "")
    warningText:SetPoint("TOPLEFT", warningFrame, "TOPLEFT", 0, -12)
    warningText:SetPoint("TOPRIGHT", warningFrame, "TOPRIGHT", 0, -12)
    warningText:SetText("Creating, deleting, or switching between profiles will require a |cFFFFD100RELOAD|r.\n\nScoot only layers customizations on top of the Blizzard UI and a reload is needed to obtain current defaults for fields which you have customized in one profile but not another.")
    warningText:SetTextColor(1.0, 0.82, 0.0, 1)
    warningText:SetJustifyH("CENTER")
    warningText:SetWordWrap(true)

    table.insert(state.currentControls, warningFrame)
    yOffset = yOffset - 100

    ---------------------------------------------------------------------------
    -- Set scroll content height
    ---------------------------------------------------------------------------
    local totalHeight = math.abs(yOffset) + 20
    scrollContent:SetHeight(totalHeight)
end

addon.UI.SettingsPanel:RegisterRenderer("profilesManage", function(panel, scrollContent)
    Manage.Render(panel, scrollContent)
end)

return Manage
