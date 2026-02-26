local addonName, addon = ...

addon.Presets = addon.Presets or {}
local Presets = addon.Presets

local registry = {}
local order = {}

local function deepCopy(tbl)
    if not tbl then return nil end
    return CopyTable(tbl)
end

local function normalizeId(id)
    if type(id) ~= "string" then return nil end
    id = id:lower():gsub("%s+", "_")
    return id
end

function Presets:Register(data)
    if type(data) ~= "table" then
        error("Preset data must be a table", 2)
    end
    local id = normalizeId(data.id or data.name)
    if not id or id == "" then
        error("Preset requires an id or name", 2)
    end
    if registry[id] then
        error("Preset '" .. id .. "' already registered", 2)
    end

    local entry = deepCopy(data)
    entry.id = id
    entry.name = data.name or id
    entry.version = data.version or "PENDING"
    entry.wowBuild = tostring(data.wowBuild or "")
    entry.description = data.description or ""
    entry.previewTexture = data.previewTexture or "Interface\\AddOns\\Scoot\\media\\presets\\Scoot"
    entry.previewThumbnail = data.previewThumbnail or entry.previewTexture
    entry.tags = data.tags or {}
    entry.comingSoon = not not data.comingSoon
    entry.requiresConsolePort = not not data.requiresConsolePort
    entry.recommendedInput = data.recommendedInput or (entry.requiresConsolePort and "ConsolePort" or "Mouse + Keyboard")
    entry.screenClass = data.screenClass or "desktop"
    entry.lastUpdated = data.lastUpdated or date("%Y-%m-%d")
    entry.editModeExport = data.editModeExport
    entry.editModeSha256 = data.editModeSha256
    entry.sourceLayoutName = data.sourceLayoutName
    entry.scootProfile = data.scootProfile
    entry.profileSha256 = data.profileSha256
    entry.consolePortProfile = data.consolePortProfile
    entry.consolePortSha256 = data.consolePortSha256
    entry.notes = data.notes
    entry.designedFor = data.designedFor or {}
    entry.recommends = data.recommends or {}

    registry[id] = entry
    table.insert(order, id)
    -- Preserve registration order (ScooterUI first, then ScooterDeck)
end

function Presets:GetList()
    local list = {}
    for _, id in ipairs(order) do
        list[#list + 1] = registry[id]
    end
    return list
end

function Presets:GetPreset(id)
    if not id then return nil end
    return registry[normalizeId(id)] or registry[id]
end

function Presets:HasConsolePort()
    return _G.ConsolePort ~= nil
end

function Presets:CheckDependencies(preset)
    if not preset then
        return false, "Preset not found."
    end
    if preset.requiresConsolePort and not self:HasConsolePort() then
        return false, "ConsolePort must be installed to import this preset."
    end
    return true
end

function Presets:IsPayloadReady(preset)
    if not preset then return false end
    if not preset.scootProfile then
        return false
    end
    local hasEditMode = (type(preset.editModeLayout) == "table")
        or (type(preset.sourceLayoutName) == "string" and preset.sourceLayoutName ~= "")
    if not hasEditMode then
        return false
    end
    return true
end

function Presets:ApplyPreset(id, opts)
    local preset = self:GetPreset(id)
    if not preset then
        return false, "Preset not found."
    end
    local ok, depErr = self:CheckDependencies(preset)
    if not ok then
        return false, depErr
    end
    if not self:IsPayloadReady(preset) then
        return false, "Preset payload has not shipped yet."
    end
    if InCombatLockdown and InCombatLockdown() then
        return false, "Cannot import presets during combat."
    end
    if not addon.EditMode or not addon.EditMode.ImportPresetLayout then
        return false, "Preset import helper is not available."
    end
    return addon.EditMode:ImportPresetLayout(preset, opts or {})
end

function Presets:GetDefaultPresetId()
    return order[1]
end

--[[----------------------------------------------------------------------------
    ApplyPresetFromUI - UI flow for applying a preset with dialogs
    Moved from legacy panel to core so both UI versions can use it.
----------------------------------------------------------------------------]]--

-- Helper to get editable (non-Blizzard-preset) layouts for the "Apply to Existing" flow
local function getEditableLayoutsForPresetTarget()
    local layouts = {}
    if addon.Profiles and addon.Profiles.GetAvailableLayouts then
        local editable, _ = addon.Profiles:GetAvailableLayouts()
        for _, name in ipairs(editable or {}) do
            -- Exclude Blizzard presets (Modern, Classic) - they cannot be overwritten
            if name ~= "Modern" and name ~= "Classic" then
                table.insert(layouts, name)
            end
        end
    end
    return layouts
end

-- Show a TUI-styled dialog for selecting existing layout
local function showExistingLayoutSelector(preset, onSelect, onCancel)
    local presetName = preset.name or preset.id or "Preset"
    local layouts = getEditableLayoutsForPresetTarget()

    if #layouts == 0 then
        addon:Print("No existing editable layouts found.")
        if onCancel then onCancel() end
        return
    end

    -- Build list options for the dialog
    local listOptions = {}
    for _, name in ipairs(layouts) do
        table.insert(listOptions, { value = name, label = name })
    end

    addon.Dialogs:Show("SCOOT_SELECT_EXISTING_LAYOUT", {
        formatArgs = { presetName },
        listOptions = listOptions,
        selectedValue = layouts[1],
        onAccept = function(data, _, selectedValue)
            if onSelect and selectedValue then
                onSelect(selectedValue)
            end
        end,
        onCancel = onCancel,
    })
end

function Presets:ApplyPresetFromUI(preset)
    if not preset then return end
    if not self.ApplyPreset then
        addon:Print("Preset system not initialized.")
        return
    end

    if not addon.Dialogs or not addon.Dialogs.Show then
        addon:Print("Dialogs system not initialized.")
        return
    end

    local presetName = preset.name or preset.id or "Preset"
    local defaultName = presetName

    -- Flow for creating a NEW profile (existing behavior)
    local function promptCreateNew(nameSuggestion)
        addon.Dialogs:Show("SCOOT_APPLY_PRESET", {
            formatArgs = { presetName },
            editBoxText = nameSuggestion or defaultName,
            data = { preset = preset },
            onAccept = function(d, newName)
                local function apply(importConsolePort)
                    local ok, err = Presets:ApplyPreset(d.preset.id, {
                        targetName = newName,
                        importConsolePort = importConsolePort and true or false,
                    })
                    if not ok then
                        if err and addon.Print then addon:Print(err) end
                        C_Timer.After(0, function()
                            promptCreateNew(newName)
                        end)
                        return
                    end
                    addon:Print(("Preset '%s' was created. Reloading UI to activate it..."):format(presetName))
                    -- If ReloadUI is blocked on this client, the user will see Blizzard's yellow warning.
                    -- The preset activation is still queued and will apply on the next successful reload/login.
                    ReloadUI()
                    C_Timer.After(1.0, function()
                        addon:Print("If your UI did not reload, please type /reload. The preset is queued and will activate on next load.")
                    end)
                end

                local wantsConsolePortPrompt = (d.preset and d.preset.consolePortProfile ~= nil) or (d.preset and d.preset.requiresConsolePort)
                if wantsConsolePortPrompt then
                    addon.Dialogs:Show("SCOOT_IMPORT_CONSOLEPORT", {
                        onAccept = function() apply(true) end,
                        onCancel = function() apply(false) end,
                    })
                    return
                end

                apply(false)
            end,
        })
    end

    -- Flow for applying to EXISTING profile
    local function promptApplyToExisting()
        showExistingLayoutSelector(preset, function(selectedLayout)
            -- Show overwrite confirmation
            addon.Dialogs:Show("SCOOT_PRESET_OVERWRITE_CONFIRM", {
                formatArgs = { selectedLayout, presetName },
                data = { preset = preset, targetLayout = selectedLayout },
                onAccept = function(d)
                    local ok, err = Presets:ApplyPreset(d.preset.id, { targetExisting = d.targetLayout })
                    if not ok then
                        if err and addon.Print then addon:Print(err) end
                        return
                    end
                    addon:Print(("Preset '%s' applied to '%s'. Reloading UI to activate..."):format(presetName, d.targetLayout))
                    ReloadUI()
                    C_Timer.After(1.0, function()
                        addon:Print("If your UI did not reload, please type /reload. The preset is queued and will activate on next load.")
                    end)
                end,
            })
        end, nil)
    end

    -- Check if there are existing editable layouts to offer the choice
    local editableLayouts = getEditableLayoutsForPresetTarget()

    if #editableLayouts == 0 then
        -- No existing layouts - go straight to "Create New" flow
        promptCreateNew(defaultName)
        return
    end

    -- Show the target selection dialog
    -- Accept = Create New, Cancel = Apply to Existing (Cancel button repurposed)
    addon.Dialogs:Show("SCOOT_PRESET_TARGET_CHOICE", {
        formatArgs = { presetName },
        data = { preset = preset },
        onAccept = function()
            -- User chose "Create New Profile"
            promptCreateNew(defaultName)
        end,
        onCancel = function()
            -- User chose "Apply to Existing" (the Cancel button in this dialog)
            promptApplyToExisting()
        end,
    })
end

return Presets
