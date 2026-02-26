-- ImportExportRenderer.lua - Profile Import/Export settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Profiles = addon.UI.Settings.Profiles or {}
addon.UI.Settings.Profiles.ImportExport = {}

local ImportExport = addon.UI.Settings.Profiles.ImportExport
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls

-- State management for this renderer
ImportExport._state = {
    currentControls = {},
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getActiveProfileKey()
    if addon.Profiles and addon.Profiles.GetActiveProfile then
        return addon.Profiles:GetActiveProfile()
    end
    if addon.db and addon.db.GetCurrentProfile then
        return addon.db:GetCurrentProfile()
    end
end

local function buildProfileDropdownData()
    local values = {}
    local order = {}

    if addon.Profiles and addon.Profiles.GetAvailableLayouts then
        local editable, presets = addon.Profiles:GetAvailableLayouts()
        for _, name in ipairs(editable) do
            values[name] = name
            table.insert(order, name)
        end
        for _, name in ipairs(presets) do
            values[name] = name .. " (Preset)"
            table.insert(order, name)
        end
    end

    return values, order
end

local function isCombatLocked()
    return InCombatLockdown and InCombatLockdown()
end

local function showInfoDialog(msg)
    Controls:ShowDialog(nil, {
        text = msg,
        infoOnly = true,
        acceptText = "OK",
    })
end

--------------------------------------------------------------------------------
-- performImport: executes the actual import
--------------------------------------------------------------------------------

local function performImport(envelope, targetLayoutName, editModeStr)
    if isCombatLocked() then
        showInfoDialog("Cannot import during combat. Please try again after combat ends.")
        return
    end

    if not addon.db or not addon.db.profiles then
        showInfoDialog("Profile database is not available.")
        return
    end

    -- Check whether the target layout already exists
    local isNewLayout = not (addon.Profiles._layoutLookup and addon.Profiles._layoutLookup[targetLayoutName])

    if isNewLayout then
        if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts) then
            showInfoDialog("Edit Mode API is not available.")
            return
        end

        local layoutInfo = C_EditMode.GetLayouts()
        if not layoutInfo or not layoutInfo.layouts then
            showInfoDialog("Unable to read Edit Mode layouts.")
            return
        end

        -- Check name uniqueness
        for _, l in ipairs(layoutInfo.layouts) do
            if l and l.layoutName == targetLayoutName then
                showInfoDialog("A layout with that name already exists.")
                return
            end
        end

        -- Build the new Edit Mode layout
        local newLayout
        if editModeStr and editModeStr ~= "" then
            -- Parse the provided Edit Mode string
            if C_EditMode.ConvertStringToLayoutInfo then
                local ok, parsed = pcall(C_EditMode.ConvertStringToLayoutInfo, editModeStr)
                if ok and parsed then
                    newLayout = parsed
                else
                    -- Fall back to cloning active layout
                    local activeIdx = layoutInfo.activeLayout
                    if activeIdx and layoutInfo.layouts[activeIdx] then
                        newLayout = CopyTable(layoutInfo.layouts[activeIdx])
                    end
                end
            end
        end

        if not newLayout then
            -- Clone active layout
            local activeIdx = layoutInfo.activeLayout
            if activeIdx and layoutInfo.layouts[activeIdx] then
                newLayout = CopyTable(layoutInfo.layouts[activeIdx])
            else
                -- Fallback to first preset
                for _, l in ipairs(layoutInfo.layouts) do
                    if l.layoutType == Enum.EditModeLayoutType.Preset then
                        newLayout = CopyTable(l)
                        break
                    end
                end
            end
        end

        if not newLayout then
            showInfoDialog("Unable to create new layout: no base layout found.")
            return
        end

        newLayout.layoutName = targetLayoutName
        newLayout.layoutType = Enum.EditModeLayoutType.Account
        newLayout.isPreset = nil
        newLayout.isModified = nil

        table.insert(layoutInfo.layouts, newLayout)
        C_EditMode.SaveLayouts(layoutInfo)
    end

    -- Write Scoot profile data
    addon.db.profiles[targetLayoutName] = CopyTable(envelope.data)

    -- Set pending activation token
    if addon.db.global then
        addon.db.global.pendingProfileActivation = {
            layoutName = targetLayoutName,
            reason = "ProfileImport",
        }
    end

    -- Persist AceDB profileKeys for current character
    local sv = rawget(addon.db, "sv")
    local charKey = addon.db.keys and addon.db.keys.char
    if sv and sv.profileKeys and charKey then
        sv.profileKeys[charKey] = targetLayoutName
    end

    -- Set Edit Mode active layout to the target
    if C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts then
        local li = C_EditMode.GetLayouts()
        if li and li.layouts then
            for idx, layout in ipairs(li.layouts) do
                if layout and layout.layoutName == targetLayoutName then
                    li.activeLayout = idx
                    break
                end
            end
            pcall(C_EditMode.SaveLayouts, li)
        end
    end

    ReloadUI()
end

--------------------------------------------------------------------------------
-- Import dialog chain
--------------------------------------------------------------------------------

local function showEditModeStringDialog(envelope, layoutName)
    Controls:ShowDialog(nil, {
        text = "Paste the Edit Mode export string for '" .. layoutName .. "'.\n\nLeave empty to use the active layout as a base.",
        hasEditBox = true,
        editBoxText = "",
        maxLetters = 0,
        acceptText = "Import & Reload",
        acceptWidth = 140,
        height = 220,
        onAccept = function(data, editModeStr)
            performImport(envelope, layoutName, editModeStr)
        end,
    })
end

local function showOverwriteConfirmDialog(envelope, targetName)
    Controls:ShowDialog(nil, {
        text = "This will overwrite the Scoot profile for '" .. targetName .. "'.\n\nA UI reload is required.\n\nContinue?",
        acceptText = "Import & Reload",
        acceptWidth = 140,
        height = 200,
        onAccept = function()
            performImport(envelope, targetName, nil)
        end,
    })
end

local function showNewLayoutDialog(envelope)
    Controls:ShowDialog(nil, {
        text = "Enter a name for the new profile:",
        hasEditBox = true,
        editBoxText = envelope.profileName or "Imported Profile",
        maxLetters = 64,
        acceptText = "Next",
        height = 200,
        onAccept = function(data, layoutName)
            if not layoutName or layoutName:match("^%s*$") then
                showInfoDialog("A name is required.")
                return
            end

            -- Validate name
            if C_EditMode and C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(layoutName) then
                showInfoDialog(HUD_EDIT_MODE_INVALID_LAYOUT_NAME or "Invalid layout name.")
                return
            end

            -- Check uniqueness
            if addon.Profiles._layoutLookup and addon.Profiles._layoutLookup[layoutName] then
                showInfoDialog("A layout with that name already exists.")
                return
            end

            showEditModeStringDialog(envelope, layoutName)
        end,
    })
end

local function showTargetSelectionDialog(envelope)
    -- Build list of editable layouts
    local listOptions = {
        { value = "__CREATE_NEW__", label = "Create New Edit Mode Profile" },
    }

    if addon.Profiles and addon.Profiles._sortedEditableLayouts then
        for _, name in ipairs(addon.Profiles._sortedEditableLayouts) do
            table.insert(listOptions, { value = name, label = name })
        end
    end

    local profileName = envelope.profileName or "Unknown"

    Controls:ShowDialog(nil, {
        text = "Import profile '" .. profileName .. "'\n\nSelect where to apply this profile:",
        listOptions = listOptions,
        selectedValue = "__CREATE_NEW__",
        acceptText = "Continue",
        height = 340,
        listHeight = 160,
        onAccept = function(data, editText, selectedValue)
            if selectedValue == "__CREATE_NEW__" then
                showNewLayoutDialog(envelope)
            else
                showOverwriteConfirmDialog(envelope, selectedValue)
            end
        end,
    })
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

function ImportExport.Render(panel, scrollContent)
    panel._importExportState = ImportExport._state
    panel:ClearContent()

    -- Clean up previous controls
    local state = ImportExport._state
    if state.currentControls then
        for _, control in ipairs(state.currentControls) do
            if control.Cleanup then control:Cleanup() end
            if control.Hide then control:Hide() end
            if control.SetParent then control:SetParent(nil) end
        end
    end
    state.currentControls = {}

    local ar, ag, ab = Theme:GetAccentColor()
    local dimR, dimG, dimB = Theme:GetDimTextColor()
    local fontPath = Theme:GetFont("VALUE")
    local fontPathLabel = Theme:GetFont("LABEL")

    local CONTENT_PADDING = 8
    local SECTION_GAP = 16
    local INNER_GAP = 8
    local BUTTON_WIDTH = 160
    local BUTTON_HEIGHT = 32
    local EDITBOX_WIDTH_OFFSET = 40 -- padding from each side within collapsible

    local yOffset = -CONTENT_PADDING

    -- Refresh callback
    local function refresh()
        ImportExport.Render(panel, scrollContent)
    end

    ---------------------------------------------------------------------------
    -- Info Text
    ---------------------------------------------------------------------------
    local infoFrame = CreateFrame("Frame", nil, scrollContent)
    infoFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING + 8, yOffset)
    infoFrame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING - 8, yOffset)

    local infoText = infoFrame:CreateFontString(nil, "OVERLAY")
    infoText:SetFont(fontPath, 13, "")
    infoText:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 0, 0)
    infoText:SetPoint("TOPRIGHT", infoFrame, "TOPRIGHT", 0, 0)
    infoText:SetText("Share Scoot profiles with other players, or back up your settings. Export generates a string you can copy, and Import lets you paste one in.")
    infoText:SetTextColor(dimR, dimG, dimB, 1)
    infoText:SetJustifyH("LEFT")
    infoText:SetWordWrap(true)

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
    -- EXPORT SECTION (Collapsible)
    ---------------------------------------------------------------------------
    local exportSection = Controls:CreateCollapsibleSection({
        parent = scrollContent,
        title = "Export",
        componentId = "profilesImportExport",
        sectionKey = "export",
        defaultExpanded = false,
        contentHeight = 380,
        onToggle = function()
            C_Timer.After(0, refresh)
        end,
    })
    exportSection:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, yOffset)
    exportSection:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, yOffset)
    table.insert(state.currentControls, exportSection)

    local exportContent = exportSection:GetContentFrame()
    local exportY = -INNER_GAP

    -- Export Profile Dropdown
    local exportDropdownLabel = exportContent:CreateFontString(nil, "OVERLAY")
    exportDropdownLabel:SetFont(fontPathLabel, 13, "")
    exportDropdownLabel:SetPoint("TOPLEFT", exportContent, "TOPLEFT", 12, exportY)
    exportDropdownLabel:SetText("Export Profile:")
    exportDropdownLabel:SetTextColor(ar, ag, ab, 1)
    exportY = exportY - 22

    local dropdownValues, dropdownOrder = buildProfileDropdownData()
    local selectedExportProfile = getActiveProfileKey()

    local exportDropdown = Controls:CreateDropdown({
        parent = exportContent,
        values = dropdownValues,
        order = dropdownOrder,
        get = function() return selectedExportProfile end,
        set = function(key)
            selectedExportProfile = key
        end,
        placeholder = "Select a profile...",
        width = 240,
        height = 28,
    })
    exportDropdown:SetPoint("TOPLEFT", exportContent, "TOPLEFT", 12, exportY)
    exportY = exportY - 40

    -- Scoot Profile String label
    local smStringLabel = exportContent:CreateFontString(nil, "OVERLAY")
    smStringLabel:SetFont(fontPathLabel, 12, "")
    smStringLabel:SetPoint("TOPLEFT", exportContent, "TOPLEFT", 12, exportY)
    smStringLabel:SetText("Scoot Profile String")
    smStringLabel:SetTextColor(dimR, dimG, dimB, 1)
    exportY = exportY - 18

    -- Scoot Profile MultiLineEditBox (read-only)
    local smExportBox = Controls:CreateMultiLineEditBox({
        parent = exportContent,
        width = 100, -- will be stretched via anchors
        height = 80,
        readOnly = true,
        placeholder = "Click 'Generate' to create export string...",
        fontSize = 11,
    })
    smExportBox:SetPoint("TOPLEFT", exportContent, "TOPLEFT", 12, exportY)
    smExportBox:SetPoint("TOPRIGHT", exportContent, "TOPRIGHT", -12, exportY)
    table.insert(state.currentControls, smExportBox)
    exportY = exportY - 88

    -- Generate SM Profile button
    local generateSmBtn = Controls:CreateButton({
        parent = exportContent,
        text = "Generate Profile String",
        width = BUTTON_WIDTH + 70,
        height = BUTTON_HEIGHT,
        onClick = function()
            if not selectedExportProfile then
                showInfoDialog("Please select a profile to export.")
                return
            end
            local exportStr, err = addon.ImportExport:ExportProfile(selectedExportProfile)
            if exportStr then
                smExportBox:SetText(exportStr)
                C_Timer.After(0.05, function()
                    smExportBox:SetFocus()
                    smExportBox:SelectAll()
                end)
            else
                showInfoDialog("Export failed: " .. (err or "Unknown error"))
            end
        end,
    })
    generateSmBtn:SetPoint("TOPLEFT", exportContent, "TOPLEFT", 12, exportY)
    exportY = exportY - BUTTON_HEIGHT - SECTION_GAP

    -- Edit Mode Profile String label
    local emStringLabel = exportContent:CreateFontString(nil, "OVERLAY")
    emStringLabel:SetFont(fontPathLabel, 12, "")
    emStringLabel:SetPoint("TOPLEFT", exportContent, "TOPLEFT", 12, exportY)
    emStringLabel:SetText("Edit Mode Layout String")
    emStringLabel:SetTextColor(dimR, dimG, dimB, 1)
    exportY = exportY - 18

    -- Edit Mode MultiLineEditBox (read-only)
    local emExportBox = Controls:CreateMultiLineEditBox({
        parent = exportContent,
        width = 100,
        height = 60,
        readOnly = true,
        placeholder = "Click 'Generate' to create Edit Mode string...",
        fontSize = 11,
    })
    emExportBox:SetPoint("TOPLEFT", exportContent, "TOPLEFT", 12, exportY)
    emExportBox:SetPoint("TOPRIGHT", exportContent, "TOPRIGHT", -12, exportY)
    table.insert(state.currentControls, emExportBox)
    exportY = exportY - 68

    -- Generate EM button
    local generateEmBtn = Controls:CreateButton({
        parent = exportContent,
        text = "Generate Layout String",
        width = BUTTON_WIDTH + 70,
        height = BUTTON_HEIGHT,
        onClick = function()
            if not selectedExportProfile then
                showInfoDialog("Please select a profile to export.")
                return
            end
            local exportStr, err = addon.ImportExport:ExportEditModeString(selectedExportProfile)
            if exportStr then
                emExportBox:SetText(exportStr)
                C_Timer.After(0.05, function()
                    emExportBox:SetFocus()
                    emExportBox:SelectAll()
                end)
            else
                showInfoDialog("Export failed: " .. (err or "Unknown error"))
            end
        end,
    })
    generateEmBtn:SetPoint("TOPLEFT", exportContent, "TOPLEFT", 12, exportY)

    -- Adjust export section height
    local exportContentHeight = math.abs(exportY) + BUTTON_HEIGHT + INNER_GAP
    exportSection:SetContentHeight(exportContentHeight)

    yOffset = yOffset - exportSection:GetHeight() - SECTION_GAP

    ---------------------------------------------------------------------------
    -- IMPORT SECTION (Collapsible)
    ---------------------------------------------------------------------------
    local importSection = Controls:CreateCollapsibleSection({
        parent = scrollContent,
        title = "Import",
        componentId = "profilesImportExport",
        sectionKey = "import",
        defaultExpanded = false,
        contentHeight = 280,
        onToggle = function()
            C_Timer.After(0, refresh)
        end,
    })
    importSection:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, yOffset)
    importSection:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, yOffset)
    table.insert(state.currentControls, importSection)

    local importContent = importSection:GetContentFrame()
    local importY = -INNER_GAP

    -- Import label
    local importLabel = importContent:CreateFontString(nil, "OVERLAY")
    importLabel:SetFont(fontPathLabel, 12, "")
    importLabel:SetPoint("TOPLEFT", importContent, "TOPLEFT", 12, importY)
    importLabel:SetText("Paste Scoot Profile Import String here:")
    importLabel:SetTextColor(dimR, dimG, dimB, 1)
    importY = importY - 18

    -- Import MultiLineEditBox (editable)
    local importBox = Controls:CreateMultiLineEditBox({
        parent = importContent,
        width = 100,
        height = 100,
        readOnly = false,
        placeholder = "Paste !SM1! string here...",
        fontSize = 11,
    })
    importBox:SetPoint("TOPLEFT", importContent, "TOPLEFT", 12, importY)
    importBox:SetPoint("TOPRIGHT", importContent, "TOPRIGHT", -12, importY)
    table.insert(state.currentControls, importBox)
    importY = importY - 108

    -- Import button
    local importBtn = Controls:CreateButton({
        parent = importContent,
        text = "Import Profile",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            if isCombatLocked() then
                showInfoDialog("Cannot import during combat. Please try again after combat ends.")
                return
            end

            local importStr = importBox:GetText()
            if not importStr or importStr:match("^%s*$") then
                showInfoDialog("No import string provided.")
                return
            end

            -- Strip leading/trailing whitespace
            importStr = importStr:match("^%s*(.-)%s*$")

            local success, envelopeOrError = addon.ImportExport:ImportProfile(importStr)
            if not success then
                showInfoDialog("Import failed:\n\n" .. tostring(envelopeOrError))
                return
            end

            showTargetSelectionDialog(envelopeOrError)
        end,
    })
    importBtn:SetPoint("TOPLEFT", importContent, "TOPLEFT", 12, importY)
    importY = importY - BUTTON_HEIGHT - 12

    -- Warning text
    local warningText = importContent:CreateFontString(nil, "OVERLAY")
    warningText:SetFont(fontPath, 11, "")
    warningText:SetPoint("TOPLEFT", importContent, "TOPLEFT", 12, importY)
    warningText:SetPoint("TOPRIGHT", importContent, "TOPRIGHT", -12, importY)
    warningText:SetText("Imported Scoot profiles can either be attached to an existing Edit Mode profile, or you can use an Edit Mode export string to create a new one in the next step.")
    warningText:SetTextColor(1, 0.82, 0, 0.9) -- yellow warning
    warningText:SetJustifyH("LEFT")
    warningText:SetWordWrap(true)

    -- Adjust import section height
    C_Timer.After(0, function()
        if warningText and importContent then
            local wh = warningText:GetStringHeight() or 30
            local totalH = math.abs(importY) + wh + INNER_GAP
            importSection:SetContentHeight(totalH)

            -- Update total page height
            local totalPageH = math.abs(yOffset) + importSection:GetHeight() + CONTENT_PADDING + 20
            scrollContent:SetHeight(totalPageH)
        end
    end)

    local importContentHeight = math.abs(importY) + 50 + INNER_GAP
    importSection:SetContentHeight(importContentHeight)

    yOffset = yOffset - importSection:GetHeight() - SECTION_GAP

    ---------------------------------------------------------------------------
    -- Set total scroll content height
    ---------------------------------------------------------------------------
    local totalPageHeight = math.abs(yOffset) + CONTENT_PADDING + 20
    scrollContent:SetHeight(totalPageHeight)
end

addon.UI.SettingsPanel:RegisterRenderer("profilesImportExport", function(panel, scrollContent)
    ImportExport.Render(panel, scrollContent)
end)
