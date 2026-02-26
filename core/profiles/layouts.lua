local _, addon = ...
local Profiles = addon.Profiles
local LEO = LibStub and LibStub("LibEditModeOverride-1.0")

-- Aliases for internals promoted by core.lua
local Debug = addon.Profiles._Debug
local deepCopy = addon.Profiles._deepCopy
local ensureLayoutsLoaded = addon.Profiles._ensureLayoutsLoaded
local isCombatLocked = addon.Profiles._isCombatLocked
local normalizeName = addon.Profiles._normalizeName
local notifyUI = addon.Profiles._notifyUI
local postMutationSync = addon.Profiles._postMutationSync
local addLayoutToCache = addon.Profiles._addLayoutToCache

-- Layout dialogs use addon.Dialogs (see dialogs.lua).

local function layoutExists(name)
    return addon.Profiles._layoutLookup and addon.Profiles._layoutLookup[name]
end

local function setProfileAssignment(cfg, fromName, toName)
    if not cfg or not cfg.assignments then return end
    for specID, profile in pairs(cfg.assignments) do
        if profile == fromName then
            cfg.assignments[specID] = toName
        end
    end
end

function Profiles:GetLayoutDisplayText(layoutName)
    if not layoutName then return nil end
    for _, entry in ipairs(self:GetLayoutMenuEntries() or {}) do
        if entry.key == layoutName then
            return entry.text
        end
    end
    return layoutName
end

function Profiles:PromptClonePreset(presetName, dropdown, displayText, previousKey, suggested)
    self:RestoreDropdownSelection(dropdown, previousKey, self:GetLayoutDisplayText(previousKey))
    local data = {
        presetName = presetName,
        dropdown = dropdown,
        displayText = displayText,
        previousKey = previousKey,
        previousText = self:GetLayoutDisplayText(previousKey),
    }
    local defaultName = suggested or ((presetName or "Preset") .. " Copy")
    addon.Dialogs:Show("SCOOT_CLONE_PRESET", {
        formatArgs = { displayText or presetName or "Preset" },
        editBoxText = defaultName,
        data = data,
        onAccept = function(d, newName)
            local success, err = addon.Profiles:ClonePresetLayout(d, newName)
            if not success then
                if err and addon and addon.Print then addon:Print(err) end
                C_Timer.After(0, function()
                    addon.Profiles:PromptClonePreset(d.presetName, d.dropdown, d.displayText, d.previousKey, newName)
                end)
            end
        end,
        onCancel = function(d)
            addon.Profiles:RestoreDropdownSelection(d.dropdown, d.previousKey, d.previousText)
        end,
    })
end

function Profiles:PromptRenameLayout(currentName, dropdown, suggested)
    if not currentName or self:IsPreset(currentName) then return end
    local data = {
        currentName = currentName,
        currentText = self:GetLayoutDisplayText(currentName),
        dropdown = dropdown,
    }
    addon.Dialogs:Show("SCOOT_RENAME_LAYOUT", {
        editBoxText = suggested or currentName or "",
        data = data,
        onAccept = function(d, newName)
            local success, err = addon.Profiles:PerformRenameLayout(d.currentName, newName)
            if not success then
                if err and addon and addon.Print then addon:Print(err) end
                C_Timer.After(0, function()
                    addon.Profiles:PromptRenameLayout(d.currentName, d.dropdown, newName)
                end)
            end
        end,
        onCancel = function(d)
            addon.Profiles:RestoreDropdownSelection(d.dropdown, d.currentName, d.currentText)
        end,
    })
end

function Profiles:PromptCopyLayout(sourceName, dropdown, suggested)
    if not sourceName then return end
    local data = {
        sourceName = sourceName,
        sourceText = self:GetLayoutDisplayText(sourceName),
        dropdown = dropdown,
    }
    local defaultName = suggested or ((sourceName or "Layout") .. " Copy")
    addon.Dialogs:Show("SCOOT_COPY_LAYOUT", {
        formatArgs = { sourceName or "" },
        editBoxText = defaultName,
        data = data,
        onAccept = function(d, newName)
            local success, err = addon.Profiles:PerformCopyLayout(d.sourceName, newName)
            if not success then
                if err and addon and addon.Print then addon:Print(err) end
                C_Timer.After(0, function()
                    addon.Profiles:PromptCopyLayout(d.sourceName, d.dropdown, newName)
                end)
            else
                -- Copy no longer switches profiles (no reload needed). Keep the current selection.
                if d and d.dropdown and addon and addon.Profiles and addon.Profiles.db then
                    local current = addon.Profiles.db:GetCurrentProfile()
                    addon.Profiles:RestoreDropdownSelection(d.dropdown, current, addon.Profiles:GetLayoutDisplayText(current))
                end
            end
        end,
        onCancel = function(d)
            addon.Profiles:RestoreDropdownSelection(d.dropdown, d.sourceName, d.sourceText)
        end,
    })
end

function Profiles:PromptCreateLayout(dropdown, suggested)
    local data = {
        dropdown = dropdown,
    }
    local defaultName = suggested or "New Layout"
    addon.Dialogs:Show("SCOOT_CREATE_LAYOUT", {
        editBoxText = defaultName,
        data = data,
        onAccept = function(d, newName)
            local success, err = addon.Profiles:PerformCreateLayout(newName)
            if not success then
                if err and addon and addon.Print then addon:Print(err) end
                C_Timer.After(0, function()
                    addon.Profiles:PromptCreateLayout(d.dropdown, newName)
                end)
            end
        end,
        onCancel = function(d)
            if d and d.dropdown and addon and addon.Profiles and addon.Profiles.db then
                local current = addon.Profiles.db:GetCurrentProfile()
                addon.Profiles:RestoreDropdownSelection(d.dropdown, current, addon.Profiles:GetLayoutDisplayText(current))
            end
        end,
    })
end

function Profiles:ConfirmDeleteLayout(layoutName, dropdown)
    if not layoutName or self:IsPreset(layoutName) then return end
    local data = {
        layoutName = layoutName,
        layoutText = self:GetLayoutDisplayText(layoutName),
        dropdown = dropdown,
    }
    addon.Dialogs:Show("SCOOT_DELETE_LAYOUT", {
        formatArgs = { layoutName or "" },
        data = data,
        onAccept = function(d)
            local success, err = addon.Profiles:PerformDeleteLayout(d.layoutName)
            if not success and err and addon and addon.Print then
                addon:Print(err)
            end
        end,
        onCancel = function(d)
            addon.Profiles:RestoreDropdownSelection(d.dropdown, d.layoutName, d.layoutText)
        end,
    })
end

function Profiles:ClonePresetLayout(data, rawName)
    if isCombatLocked() then
        return false, "Cannot modify layouts during combat."
    end
    if not ensureLayoutsLoaded() then
        return false, "Edit Mode layouts are not ready yet."
    end
    local presetName = data and data.presetName
    local dropdown = data and data.dropdown
    local newName = normalizeName(rawName)
    if not newName then
        return false, "A name is required."
    end
    if C_EditMode and C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(newName) then
        return false, HUD_EDIT_MODE_INVALID_LAYOUT_NAME or "Invalid layout name."
    end
    if self._layoutLookup and self._layoutLookup[newName] then
        return false, "A layout with that name already exists."
    end

    -- COMPLETELY AVOID EditModeManagerFrame - use only C_EditMode APIs
    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then
        return false, "C_EditMode API unavailable." end

    -- Get the current layout structure
    local layoutInfo = C_EditMode.GetLayouts()
    if not layoutInfo or not layoutInfo.layouts then
        return false, "Unable to read layouts." end

    -- Find the preset layout to clone
    local presetLayout = nil
    for _, layout in ipairs(layoutInfo.layouts) do
        if layout.layoutName == presetName and layout.layoutType == Enum.EditModeLayoutType.Preset then
            presetLayout = layout
            break
        end
    end
    if not presetLayout and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        for _, layout in ipairs(EditModePresetLayoutManager:GetCopyOfPresetLayouts() or {}) do
            if layout.layoutName == presetName then
                presetLayout = layout
                break
            end
        end
    end
    if not presetLayout then
        return false, "Unable to locate preset layout data."
    end

    -- Create a deep copy and convert to Account layout type
    local newLayout = CopyTable(presetLayout)
    newLayout.layoutType = Enum.EditModeLayoutType.Account
    newLayout.layoutName = newName
    newLayout.isPreset = nil
    newLayout.isModified = nil

    -- Add the new layout to the layouts array
    table.insert(layoutInfo.layouts, newLayout)

    -- Save directly via C_EditMode (no manager frame involvement)
    C_EditMode.SaveLayouts(layoutInfo)

    -- Reload library state and schedule sync
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    postMutationSync(self, "ClonePreset")

    -- Create AceDB profile with defaults
    addLayoutToCache(self, newName)
    self.db.profiles[newName] = deepCopy(self._profileTemplate)

    -- Defer the profile switch to avoid taint from happening in the same call stack as the copy
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            -- Now switch to the new profile normally (including Edit Mode activation)
            self:SwitchToProfile(newName, { reason = "DeferredCloneSwitch", force = true })

            -- Update UI after the switch
            if dropdown then
                self:RestoreDropdownSelection(dropdown, newName, self:GetLayoutDisplayText(newName))
            end
            notifyUI()
        end)
    else
        -- Fallback if C_Timer is unavailable
        self:SwitchToProfile(newName, { reason = "ClonePreset", force = true })
    end

    return true
end

function Profiles:RenameProfileData(oldName, newName)
    if not self.db or not self.db.profiles then return end
    if self.db.profiles[newName] then return end
    if self.db.profiles[oldName] then
        self.db.profiles[newName] = CopyTable(self.db.profiles[oldName])
        self.db.profiles[oldName] = nil
    end

    local sv = rawget(self.db, "sv")
    if sv and sv.profileKeys then
        for key, value in pairs(sv.profileKeys) do
            if value == oldName then
                sv.profileKeys[key] = newName
            end
        end
    end

    if self.db.keys and self.db.keys.profile == oldName then
        self.db.keys.profile = newName
        self.db.profile = self.db.profiles[newName]
    end

    local cfg = self:GetSpecConfig()
    setProfileAssignment(cfg, oldName, newName)
end

function Profiles:PerformRenameLayout(oldName, rawNewName)
    if not oldName then return false, "Select a layout to rename." end
    if self:IsPreset(oldName) then return false, "Preset layouts cannot be renamed." end
    if isCombatLocked() then return false, "Cannot rename layouts during combat." end
    if not ensureLayoutsLoaded() then return false, "Edit Mode layouts are not ready." end

    local newName = normalizeName(rawNewName)
    if not newName then return false, "A name is required." end
    if newName == oldName then
        return true
    end
    if C_EditMode and C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(newName) then
        return false, HUD_EDIT_MODE_INVALID_LAYOUT_NAME or "Invalid layout name."
    end
    if self._layoutLookup and self._layoutLookup[newName] then
        return false, "A layout with that name already exists." end

    local index, layout = self:FindLayoutIndex(oldName)
    if not index or not layout then
        return false, "Unable to locate the selected layout." end
    if layout.layoutType == Enum.EditModeLayoutType.Preset then
        return false, "Preset layouts cannot be renamed." end

    -- Rename using C_EditMode SaveLayouts path (avoids manager UI interactions)
    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then
        return false, "C_EditMode API unavailable." end
    local li = C_EditMode.GetLayouts()
    if not li or not li.layouts then return false, "Unable to read layouts." end
    local target
    for _, layout in ipairs(li.layouts) do
        if layout.layoutName == oldName then
            target = layout
            break
        end
    end
    if not target then return false, "Unable to locate the selected layout." end
    if target.layoutType == Enum.EditModeLayoutType.Preset then
        return false, "Preset layouts cannot be renamed." end
    target.layoutName = newName
    C_EditMode.SaveLayouts(li)
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    postMutationSync(self, "RenameLayout")

    self:RenameProfileData(oldName, newName)
    if self._layoutLookup then
        self._layoutLookup[oldName] = nil
    end
    if self._sortedEditableLayouts then
        for idx = #self._sortedEditableLayouts, 1, -1 do
            if self._sortedEditableLayouts[idx] == oldName then
                table.remove(self._sortedEditableLayouts, idx)
            end
        end
    end
    addLayoutToCache(self, newName)
    self._pendingActiveLayout = newName
    if self.db:GetCurrentProfile() == oldName then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, function()
                self:SwitchToProfile(newName, { reason = "DeferredRenameSwitch", force = true })
                notifyUI()
            end)
        else
            self:SwitchToProfile(newName, { reason = "RenameLayout", force = true })
        end
    else
        self:RequestSync("RenameLayout")
    end

    notifyUI()
    return true
end

function Profiles:PerformCopyLayout(sourceName, rawNewName)
    if not sourceName then return false, "Select a layout to copy." end
    if isCombatLocked() then return false, "Cannot copy layouts during combat." end
    if not ensureLayoutsLoaded() then return false, "Edit Mode layouts are not ready." end

    local newName = normalizeName(rawNewName)
    if not newName then return false, "A name is required." end
    if C_EditMode and C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(newName) then
        return false, HUD_EDIT_MODE_INVALID_LAYOUT_NAME or "Invalid layout name." end
    if self._layoutLookup and self._layoutLookup[newName] then
        return false, "A layout with that name already exists." end

    -- Use only C_EditMode APIs (no EditModeManagerFrame) to avoid taint

    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then
        return false, "C_EditMode API unavailable." end

    -- Get the current layout structure
    local layoutInfo = C_EditMode.GetLayouts()
    if not layoutInfo or not layoutInfo.layouts then
        return false, "Unable to read layouts." end

	-- Find the source layout in the structure (handles recent renames)
	local sourceLayout = nil
	for _, layout in ipairs(layoutInfo.layouts) do
		if layout.layoutName == sourceName then
			sourceLayout = layout
			break
		end
	end

	-- If not found, force library to reload and try again
	if not sourceLayout then
		if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
		layoutInfo = C_EditMode.GetLayouts()
		if layoutInfo and layoutInfo.layouts then
			for _, layout in ipairs(layoutInfo.layouts) do
				if layout.layoutName == sourceName then
					sourceLayout = layout
					break
				end
			end
		end
	end

	-- Fallback: if still not found, use the active layout's data (user is copying the current profile)
	if not sourceLayout and layoutInfo and layoutInfo.layouts and layoutInfo.activeLayout then
		sourceLayout = layoutInfo.layouts[layoutInfo.activeLayout]
	end

	-- prepareManager() fallback REMOVED — calling methods on EditModeManagerFrame from
	-- addon context taints all registered system frames. The C_EditMode + preset fallbacks
	-- above are sufficient to locate any source layout.

    -- If source is a preset, check the preset manager as well
    if not sourceLayout and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        for _, layout in ipairs(EditModePresetLayoutManager:GetCopyOfPresetLayouts() or {}) do
            if layout.layoutName == sourceName then
                sourceLayout = layout
                break
            end
        end
    end

	if not sourceLayout then
		return false, "Unable to locate the source layout." end

    -- Create a deep copy of the source layout
    local newLayout = CopyTable(sourceLayout)
    newLayout.layoutName = newName
    newLayout.layoutType = sourceLayout.layoutType == Enum.EditModeLayoutType.Preset
        and Enum.EditModeLayoutType.Account
        or sourceLayout.layoutType
    newLayout.isPreset = nil
    newLayout.isModified = nil

    -- Add the new layout to the layouts array
    table.insert(layoutInfo.layouts, newLayout)

    -- Save directly via C_EditMode (no manager frame involvement)
    C_EditMode.SaveLayouts(layoutInfo)

    -- Reload library state to see the new layout and schedule sync
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    postMutationSync(self, "CopyLayout")

    -- Verify copy persisted
    do
        local li = C_EditMode.GetLayouts()
        local found = false
        if li and li.layouts then
            for _, info in ipairs(li.layouts) do
                if info.layoutName == newName then found = true break end
            end
        end
        if not found then
            return false, "Copy failed to persist."
        end
    end

    -- Copy AceDB profile data
    if self.db and self.db.profiles and self.db.profiles[sourceName] then
        self.db.profiles[newName] = CopyTable(self.db.profiles[sourceName])
    else
        self.db.profiles[newName] = deepCopy(self._profileTemplate)
    end

    -- Update our internal caches
    addLayoutToCache(self, newName)

    -- Copy does NOT switch profiles (no reload needed). Just refresh UI/state.
    notifyUI()

    return true
end

function Profiles:PerformCreateLayout(rawNewName)
    if isCombatLocked() then return false, "Cannot create layouts during combat." end
    if not ensureLayoutsLoaded() then return false, "Edit Mode layouts are not ready." end

    local newName = normalizeName(rawNewName)
    if not newName then return false, "A name is required." end
    if C_EditMode and C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(newName) then
        return false, HUD_EDIT_MODE_INVALID_LAYOUT_NAME or "Invalid layout name." end
    if self._layoutLookup and self._layoutLookup[newName] then
        return false, "A layout with that name already exists." end

    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then
        return false, "C_EditMode API unavailable." end

    -- IMPORTANT: Creating a brand-new profile must be Zero‑Touch (stock Blizzard UI).
    -- We cannot reliably "undo" every frame mutation from a previous profile without
    -- tracking Blizzard baselines, so we require a /reload and let Blizzard initialize.

    local name = newName

    -- Re-validate (race-safe)
    if isCombatLocked() then
        return false, "Cannot create layouts during combat."
    end
    if not ensureLayoutsLoaded() then
        return false, "Edit Mode layouts are not ready yet."
    end

    local layoutInfo = C_EditMode.GetLayouts()
    if not layoutInfo or not layoutInfo.layouts then
        return false, "Unable to read layouts."
    end
    for _, l in ipairs(layoutInfo.layouts) do
        if l and l.layoutName == name then
            return false, "A layout with that name already exists."
        end
    end

    -- Choose a base: prefer Modern preset; fallback to active; fallback to any preset
    local base
    for _, l in ipairs(layoutInfo.layouts) do
        if l.layoutType == Enum.EditModeLayoutType.Preset and l.layoutName == "Modern" then base = l break end
    end
    if not base and layoutInfo.activeLayout and layoutInfo.layouts[layoutInfo.activeLayout] then
        base = layoutInfo.layouts[layoutInfo.activeLayout]
    end
    if not base and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        local presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts() or {}
        base = presets[1]
    end
    if not base then
        return false, "Unable to locate a base layout for creation."
    end

    local newLayout = CopyTable(base)
    newLayout.layoutName = name
    newLayout.layoutType = Enum.EditModeLayoutType.Account
    newLayout.isPreset = nil
    newLayout.isModified = nil

    table.insert(layoutInfo.layouts, newLayout)
    C_EditMode.SaveLayouts(layoutInfo)

    -- Create AceDB profile using template defaults (Zero‑Touch template is empty)
    addLayoutToCache(self, name)
    self.db.profiles[name] = deepCopy(self._profileTemplate)

    -- Persist AceDB current profile without firing our ProfileChanged apply path.
    self._suppressProfileCallback = true
    pcall(self.db.SetProfile, self.db, name)
    self._suppressProfileCallback = false

    -- EXTRA SAFETY: explicitly persist the profileKeys entry AceDB uses for this character.
    -- This ensures the newly-created profile is the one selected when the reload snapshot is written.
    do
        local sv = rawget(self.db, "sv")
        local charKey = self.db.keys and self.db.keys.char
        if sv and sv.profileKeys and charKey then
            sv.profileKeys[charKey] = name
        end
        if self.db.global then
            self.db.global.pendingProfileActivation = { layoutName = name }
        end
    end

    -- Ensure the destination is marked active in Edit Mode before reload.
    local li = C_EditMode.GetLayouts()
    if li and li.layouts then
        for idx, layout in ipairs(li.layouts) do
            if layout and layout.layoutName == name then
                li.activeLayout = idx
                break
            end
        end
        pcall(C_EditMode.SaveLayouts, li)
    end

    ReloadUI()

    return true
end

function Profiles:PerformDeleteLayout(layoutName)
    if not layoutName then return false, "Select a layout to delete." end
    if self:IsPreset(layoutName) then return false, "Preset layouts cannot be deleted." end
    if isCombatLocked() then return false, "Cannot delete layouts during combat." end
    if not ensureLayoutsLoaded() then return false, "Edit Mode layouts are not ready." end

    -- Proactively refresh the library to avoid stale lists immediately after mutations
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    local index, layout = self:FindLayoutIndex(layoutName)
    -- Do not fail early on a stale C_EditMode list; manager lookup below is authoritative

    local currentProfile = self.db:GetCurrentProfile()
    if currentProfile == layoutName then
        local fallback
        for _, entry in ipairs(self:GetLayoutMenuEntries() or {}) do
            if entry.key ~= layoutName and not entry.preset then
                fallback = entry.key
                break
            end
        end
        if not fallback then
            local tempName = "New Layout"
            local suffix = 1
            while self._layoutLookup and self._layoutLookup[tempName] do
                suffix = suffix + 1
                tempName = "New Layout " .. suffix
            end
            local success = self:ClonePresetLayout({ presetName = "Modern" }, tempName)
            if success then
                fallback = tempName
            end
        end
        if not fallback or fallback == layoutName then
            return false, "Unable to select a replacement layout before deleting." end
        self:SwitchToProfile(fallback, { reason = "DeleteFallback", force = true })
    end

    -- Delete using direct C_EditMode APIs (no EditModeManagerFrame interaction to avoid taint).
    -- Pattern follows LibEditModeOverride:DeleteLayout().
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts and C_EditMode.OnLayoutDeleted) then
        return false, "C_EditMode API unavailable."
    end
    local li = C_EditMode.GetLayouts()
    if not li or not li.layouts then return false, "Unable to read layouts." end
    local deleteIndex
    for i, info in ipairs(li.layouts) do
        if info.layoutName == layoutName then
            if info.layoutType == Enum.EditModeLayoutType.Preset then
                return false, "Preset layouts cannot be deleted."
            end
            deleteIndex = i
            break
        end
    end
    if not deleteIndex then return false, "Layout not found." end
    table.remove(li.layouts, deleteIndex)
    C_EditMode.SaveLayouts(li)
    -- Defer OnLayoutDeleted to a clean execution context (adjusts activeLayout + fires event)
    C_Timer.After(0, function()
        pcall(C_EditMode.OnLayoutDeleted, deleteIndex)
    end)

    -- Refresh library/cache and UI after successful delete
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    postMutationSync(self, "DeleteLayout")

    if self.db and self.db.profiles then
        self.db.profiles[layoutName] = nil
    end
    if self._layoutLookup then
        self._layoutLookup[layoutName] = nil
    end
    if self._sortedEditableLayouts then
        for i = #self._sortedEditableLayouts, 1, -1 do
            if self._sortedEditableLayouts[i] == layoutName then
                table.remove(self._sortedEditableLayouts, i)
            end
        end
    end
    local sv = rawget(self.db, "sv")
    if sv and sv.profileKeys then
        for key, value in pairs(sv.profileKeys) do
            if value == layoutName then
                sv.profileKeys[key] = nil
            end
        end
    end
    local cfg = self:GetSpecConfig()
    if cfg and cfg.assignments then
        for specID, profileName in pairs(cfg.assignments) do
            if profileName == layoutName then
                cfg.assignments[specID] = nil
            end
        end
    end

    self:RequestSync("DeleteLayout")
    notifyUI()
    if addon and addon.EditMode and addon.EditMode.RefreshSyncAndNotify then
        addon.EditMode.RefreshSyncAndNotify("DeleteLayout")
    end
    return true
end
