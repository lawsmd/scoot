local _, addon = ...
local LEO = LibStub("LibEditModeOverride-1.0")

--[[----------------------------------------------------------------------------
    Preset import helpers (ScooterUI / ScooterDeck)
----------------------------------------------------------------------------]]--
local function computeSha256(blob)
    if type(blob) ~= "string" or blob == "" then
        return nil
    end
    if not C_Crypto or type(C_Crypto.Hash) ~= "function" then
        return nil
    end
    local ok, hash = pcall(C_Crypto.Hash, "SHA256", blob)
    if not ok or type(hash) ~= "string" then
        return nil
    end
    return string.lower(hash)
end

local function verifyHash(expected, blob, label)
    if not expected or expected == "" then
        return true
    end
    local computed = computeSha256(blob or "")
    if not computed then
        -- Some clients/accounts do not expose C_Crypto.Hash. Hash validation is a
        -- safety rail (drift/tamper detection) but should not block functionality.
        -- We warn once per session and proceed.
        if addon and not addon._warnedPresetHashUnavailable then
            addon._warnedPresetHashUnavailable = true
            if addon.Print then
                addon:Print(string.format("%s hash check skipped: SHA256 API unavailable on this client.", label))
            end
        end
        return true
    end
    if computed ~= string.lower(expected) then
        return false, string.format("%s hash mismatch (expected %s, got %s).", label, expected, computed)
    end
    return true
end

local function verifyLayoutHash(expected, layoutInfo, label)
    if not expected or expected == "" then
        return true
    end
    if not C_EditMode or type(C_EditMode.ConvertLayoutInfoToString) ~= "function" then
        return false, string.format("%s hash could not be computed on this client (ConvertLayoutInfoToString unavailable).", label)
    end
    local ok, exportString = pcall(C_EditMode.ConvertLayoutInfoToString, layoutInfo)
    if not ok or type(exportString) ~= "string" or exportString == "" then
        return false, string.format("%s hash could not be computed on this client (export conversion failed).", label)
    end
    return verifyHash(expected, exportString, label)
end

local function buildPresetInstanceName(preset)
    local base = (preset and preset.name) or "Preset"
    base = base:gsub("^%s+", ""):gsub("%s+$", "")
    if base == "" then base = "Preset" end
    local stamp = date and date("!%Y-%m-%d %H:%M") or tostring(time() or "")
    local name = string.format("%s %s", base, stamp)
    if #name > 32 then
        name = name:sub(1, 32)
    end
    local attempt = name
    local suffix = 2
    local lookup = addon and addon.Profiles and addon.Profiles._layoutLookup or {}
    while lookup[attempt] do
        local trimmed = name
        local avail = math.max(6, 32 - (#tostring(suffix) + 1))
        if #trimmed > avail then
            trimmed = trimmed:sub(1, avail)
        end
        attempt = string.format("%s-%d", trimmed, suffix)
        suffix = suffix + 1
    end
    return attempt
end

local function cloneProfilePayload(preset, layoutName)
    local payload = preset and preset.scootProfile
    if type(payload) ~= "table" then
        return nil, "Preset Scoot profile payload missing."
    end
    local copy = CopyTable(payload)
    copy.__preset = true
    copy.__presetSource = preset.id or preset.name or "preset"
    copy.__presetVersion = preset.version or "PENDING"
    copy.__presetLayout = layoutName
    return copy
end

local function _NormalizeLayoutName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return name
end

local function _LayoutNameExists(name)
    if not name then return false end
    if C_EditMode and type(C_EditMode.GetLayouts) == "function" then
        local li = C_EditMode.GetLayouts()
        if li and type(li.layouts) == "table" then
            for _, layout in ipairs(li.layouts) do
                if layout and layout.layoutName == name then
                    return true
                end
            end
        end
    end
    return false
end

local function importConsolePortProfile(preset, profileName)
    if not preset or preset.consolePortProfile == nil then
        return true
    end

    -- ConsolePort is an external addon suite. If it's not loaded, we do not fail
    -- the preset import (Scoot profile + Edit Mode layout are still valid).
    if not _G.ConsolePort and not _G.ConsolePortSettings then
        return false, "ConsolePort is not loaded. Enable ConsolePort and reload, then try importing the preset again."
    end

    local data = preset.consolePortProfile
    if type(data) ~= "table" then
        return false, "ConsolePort payload is invalid (expected a table)."
    end

    -- Import strategy:
    -- Write ConsolePort's SavedVariables globals directly, then rely on the UI reload
    -- (prompted by the preset flow) to persist these values to disk.
    for k, v in pairs(data) do
        if type(k) == "string" and k:match("^ConsolePort") then
            if type(v) == "table" then
                _G[k] = CopyTable(v)
            else
                _G[k] = v
            end
        end
    end

    return true
end

function addon.EditMode:ImportPresetLayout(preset, opts)
    opts = opts or {}
    if type(preset) ~= "table" then
        return false, "Preset metadata missing."
    end
    local hasLayoutTable = type(preset.editModeLayout) == "table"
    local hasLegacyExport = type(preset.editModeExport) == "string" and preset.editModeExport ~= ""
    local hasSourceLayoutName = type(preset.sourceLayoutName) == "string" and preset.sourceLayoutName ~= ""
    if hasLegacyExport and not hasLayoutTable then
        return false, "Preset uses legacy Edit Mode export string format. Re-capture the preset with a raw layout table via /scoot debug editmode export and update the preset payload file under core/preset_*.lua (for example core/preset_scooterui.lua)."
    end
    if not hasLayoutTable and not hasSourceLayoutName then
        return false, "Preset Edit Mode payload missing (requires editModeLayout or sourceLayoutName)."
    end
    if InCombatLockdown and InCombatLockdown() then
        return false, "Cannot import presets during combat."
    end
    if not C_EditMode or type(C_EditMode.GetLayouts) ~= "function" or type(C_EditMode.SaveLayouts) ~= "function" then
        return false, "C_EditMode GetLayouts/SaveLayouts API unavailable."
    end
    if not LEO or not (LEO.IsReady and LEO:IsReady()) then
        return false, "Edit Mode library is not ready."
    end

    self.LoadLayouts()

    if hasLayoutTable then
        -- Skip hash validation if placeholder value (development mode)
        if preset.editModeSha256 ~= "PENDING" then
            local okHash, hashErr = verifyLayoutHash(preset.editModeSha256, preset.editModeLayout, "Edit Mode layout")
            if not okHash then return false, hashErr end
        end
    end

    ---------------------------------------------------------------------------
    -- APPLY TO EXISTING LAYOUT PATH (Cross-machine sync feature)
    -- When targetExisting is specified, overwrite the existing layout + profile
    -- instead of creating new ones.
    ---------------------------------------------------------------------------
    if opts and opts.targetExisting then
        local targetName = opts.targetExisting
        
        -- Validate the target exists and is editable (not a Blizzard preset)
        local li = C_EditMode.GetLayouts()
        if not (li and type(li.layouts) == "table") then
            return false, "Unable to read layouts."
        end
        
        local targetLayout, targetIndex
        for idx, layout in ipairs(li.layouts) do
            if layout and layout.layoutName == targetName then
                targetLayout = layout
                targetIndex = idx
                break
            end
        end
        
        if not targetLayout then
            return false, string.format("Target layout '%s' not found.", targetName)
        end
        
        -- Block overwriting Blizzard presets
        if targetLayout.layoutType == (Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Preset) then
            return false, "Cannot overwrite Blizzard preset layouts (Modern/Classic). Please select an editable layout."
        end
        
        -- Clone the profile payload
        local profileCopy, profileErr = cloneProfilePayload(preset, targetName)
        if not profileCopy then
            return false, profileErr
        end
        
        -- Dry run check
        if opts.dryRun then
            return true, targetName
        end
        
        -- OVERWRITE Edit Mode layout systems/settings
        if hasLayoutTable then
            -- Copy systems and settings from preset's editModeLayout to target layout
            local presetLayout = preset.editModeLayout
            if presetLayout.systems and targetLayout.systems then
                -- Build a map of preset systems by key
                local function indexSystems(layout)
                    local map = {}
                    for _, sys in ipairs(layout.systems) do
                        map[(sys.system or 0) .. ":" .. (sys.systemIndex or 0)] = sys
                    end
                    return map
                end
                local presetMap = indexSystems(presetLayout)
                
                -- Copy settings from preset to target
                for _, dsys in ipairs(targetLayout.systems) do
                    local key = (dsys.system or 0) .. ":" .. (dsys.systemIndex or 0)
                    local ssys = presetMap[key]
                    if ssys then
                        -- Copy anchor and default-position flags
                        if ssys.anchorInfo and dsys.anchorInfo then
                            dsys.isInDefaultPosition = not not ssys.isInDefaultPosition
                            local sa, da = ssys.anchorInfo, dsys.anchorInfo
                            da.point = sa.point
                            da.relativePoint = sa.relativePoint
                            da.offsetX = sa.offsetX
                            da.offsetY = sa.offsetY
                            da.relativeTo = sa.relativeTo
                        end
                        -- Copy individual setting values by numeric id
                        local svalById = {}
                        if ssys.settings then
                            for _, it in ipairs(ssys.settings) do
                                svalById[it.setting] = it.value
                            end
                        end
                        if dsys.settings then
                            for _, it in ipairs(dsys.settings) do
                                local v = svalById[it.setting]
                                if v ~= nil then it.value = v end
                            end
                        end
                    end
                end
            end
        end
        -- Note: sourceLayoutName fallback for "apply to existing" is intentionally not supported
        -- since the preset should always have a captured editModeLayout table.
        
        -- Save the modified layouts
        C_EditMode.SaveLayouts(li)
        
        -- Ensure LibEditModeOverride sees the changes immediately
        if LEO and LEO.LoadLayouts then
            pcall(LEO.LoadLayouts, LEO)
        end
        
        self.SaveOnly()
        
        if addon and addon.Profiles and addon.Profiles.RequestSync then
            addon.Profiles:RequestSync("PresetOverwrite")
        end
        
        if not addon or not addon.db or not addon.db.profiles then
            return false, "AceDB not initialized."
        end
        
        -- OVERWRITE the Scoot profile data
        if type(profileCopy) == "table" then
            profileCopy.__presetLayout = targetName
        end
        addon.db.profiles[targetName] = profileCopy
        
        -- Import ConsolePort profile if present (ScooterDeck)
        local cpOk, cpErr = importConsolePortProfile(preset, targetName)
        if not cpOk then
            addon:Print(cpErr)
        end
        
        addon:Print(string.format("Applied preset '%s' to existing layout '%s'.", preset.name or preset.id or "Preset", targetName))
        
        -- Queue activation for next reload
        if addon and addon.db and addon.db.global then
            addon.db.global.pendingPresetActivation = {
                layoutName = targetName,
                presetId = preset.id or preset.name,
                createdAt = date and date("%Y-%m-%d %H:%M:%S") or nil,
                appliedToExisting = true,
            }
        end
        
        return true, targetName
    end

    ---------------------------------------------------------------------------
    -- CREATE NEW LAYOUT PATH (Original behavior)
    ---------------------------------------------------------------------------

    -- Determine target layout/profile name (user-specified or auto-generated)
    local newLayoutName
    if opts and opts.targetName then
        newLayoutName = _NormalizeLayoutName(opts.targetName)
        if not newLayoutName then
            return false, "A name is required."
        end
        if C_EditMode and type(C_EditMode.IsValidLayoutName) == "function" and not C_EditMode.IsValidLayoutName(newLayoutName) then
            return false, HUD_EDIT_MODE_INVALID_LAYOUT_NAME or "Invalid layout name."
        end
        if _LayoutNameExists(newLayoutName) then
            return false, "A layout with that name already exists."
        end
        if addon and addon.db and addon.db.profiles and addon.db.profiles[newLayoutName] then
            return false, "A Scoot profile with that name already exists."
        end
    else
        newLayoutName = buildPresetInstanceName(preset)
    end

    local profileCopy, profileErr = cloneProfilePayload(preset, newLayoutName)
    if not profileCopy then
        return false, profileErr
    end
    if opts and opts.dryRun then
        -- Validate that the Edit Mode payload source is available without mutating
        -- layouts or AceDB state. Useful for authoring and CI-style checks.
        if not hasLayoutTable and hasSourceLayoutName then
            local li = C_EditMode.GetLayouts()
            local found = false
            if li and type(li.layouts) == "table" then
                for _, layout in ipairs(li.layouts) do
                    if layout and layout.layoutName == preset.sourceLayoutName then
                        found = true
                        break
                    end
                end
            end
            if not found then
                return false, "Dry run failed: source layout not found: " .. tostring(preset.sourceLayoutName)
            end
        end
        return true, newLayoutName
    end
    if hasLayoutTable then
        local li = C_EditMode.GetLayouts()
        if not (li and type(li.layouts) == "table") then
            return false, "Unable to read layouts."
        end
        local newLayout = CopyTable(preset.editModeLayout)
        newLayout.layoutName = newLayoutName
        newLayout.layoutType = Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account or newLayout.layoutType
        newLayout.isPreset = nil
        newLayout.isModified = nil
        table.insert(li.layouts, newLayout)
        C_EditMode.SaveLayouts(li)
    else
        -- Development / authoring fallback:
        -- Clone an existing layout by name using C_EditMode.GetLayouts() + SaveLayouts().
        local li = C_EditMode.GetLayouts()
        if not (li and type(li.layouts) == "table") then
            return false, "Unable to read layouts."
        end
        local source
        for _, layout in ipairs(li.layouts) do
            if layout and layout.layoutName == preset.sourceLayoutName then
                source = layout
                break
            end
        end
        if not source then
            return false, "Source layout not found for preset: " .. tostring(preset.sourceLayoutName)
        end
        local newLayout = CopyTable(source)
        newLayout.layoutName = newLayoutName
        newLayout.layoutType = Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account or newLayout.layoutType
        newLayout.isPreset = nil
        newLayout.isModified = nil
        table.insert(li.layouts, newLayout)
        C_EditMode.SaveLayouts(li)
    end

    -- Ensure LibEditModeOverride sees the new layout immediately (avoids stale caches)
    if LEO and LEO.LoadLayouts then
        pcall(LEO.LoadLayouts, LEO)
    end

    self.SaveOnly()

    if addon and addon.Profiles and addon.Profiles.RequestSync then
        addon.Profiles:RequestSync("PresetImport")
    end

    if not addon or not addon.db or not addon.db.profiles then
        return false, "AceDB not initialized."
    end
    -- Ensure the profile metadata points at the final layout name (ImportLayout may
    -- return a modified name in some edge cases).
    if type(profileCopy) == "table" then
        profileCopy.__presetLayout = newLayoutName
    end
    addon.db.profiles[newLayoutName] = profileCopy

    if opts and opts.importConsolePort then
        local cpOk, cpErr = importConsolePortProfile(preset, newLayoutName)
        if not cpOk then
            addon:Print(cpErr)
        end
    end

    addon:Print(string.format("Imported preset '%s' as new layout '%s'.", preset.name or preset.id or "Preset", newLayoutName))

    -- Do NOT attempt to activate the new layout/profile immediately.
    -- Some clients block add-ons from chaining layout creation -> activation -> reload in one session,
    -- yielding "Interface action failed because of an AddOn" and leaving the user on the old profile.
    -- Instead, persist a pending activation token and let the next load perform the switch.
    if addon and addon.db and addon.db.global then
        addon.db.global.pendingPresetActivation = {
            layoutName = newLayoutName,
            presetId = preset.id or preset.name,
            createdAt = date and date("%Y-%m-%d %H:%M:%S") or nil,
        }
    end

    return true, newLayoutName
end
