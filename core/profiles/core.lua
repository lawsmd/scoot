local addonName, addon = ...

addon.Profiles = addon.Profiles or {}
local Profiles = addon.Profiles

local LEO = LibStub and LibStub("LibEditModeOverride-1.0")

local DEBUG_PREFIX = "|cffa0ff00ScootProfiles|r"

local function Debug(...)
    if not addon or not addon._dbgProfiles then return end
    local messages = {}
    for i = 1, select("#", ...) do
        messages[#messages + 1] = tostring(select(i, ...))
    end
    local msg = table.concat(messages, " ")
    if addon.Print then
        addon:Print(DEBUG_PREFIX .. " " .. msg)
    else
        print(DEBUG_PREFIX, msg)
    end
end

local function deepCopy(tbl)
    if not tbl then return {} end
    return CopyTable(tbl)
end

local function ensureLayoutsLoaded()
    if not LEO then return false end
    if not (LEO.IsReady and LEO:IsReady()) then
        return false
    end
    if LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then
        if LEO.LoadLayouts then
            local ok = pcall(LEO.LoadLayouts, LEO)
            if not ok then
                return false
            end
        else
            return false
        end
    end
    return true
end

local layoutTypeLabels = {}
if Enum and Enum.EditModeLayoutType then
    layoutTypeLabels[Enum.EditModeLayoutType.Preset] = "Preset"
    layoutTypeLabels[Enum.EditModeLayoutType.Character] = "Character"
    layoutTypeLabels[Enum.EditModeLayoutType.Account] = "Account"
    layoutTypeLabels[Enum.EditModeLayoutType.Override] = "Override"
end

local function LayoutTypeName(layoutType)
    if not layoutType then return "Unknown" end
    return layoutTypeLabels[layoutType] or ("Type" .. tostring(layoutType))
end

local function ensureEditModeFrame()
    if not EditModeManagerFrame or not EditModeManagerFrame.MakeNewLayout then
        if C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_EditMode")
        end
    end
    return EditModeManagerFrame
end

-- prepareManager() REMOVED — calling methods on EditModeManagerFrame from addon context
-- taints ALL registered system frames at once (via UpdateSystems → secureexecuterange).
-- All callers replaced with direct C_EditMode API reads (GetLayouts/SaveLayouts).

-- Apply the profile's CDM override (if explicitly set) to the Blizzard CVar.
-- This is character-scoped in Blizzard, so we enforce per-profile by setting it
-- when the active Scoot profile changes.
local function ApplyCooldownViewerEnabledForActiveProfile(reason)
    local profile = addon and addon.db and addon.db.profile
    local q = profile and profile.cdmQoL
    local desired = q and q.enableCDM
    if desired == nil then
        return
    end
    local value = (desired and "1") or "0"

    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "cooldownViewerEnabled", value)
        elseif SetCVar then
            pcall(SetCVar, "cooldownViewerEnabled", value)
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            applyCVar()
        end)
    else
        applyCVar()
    end

    -- Important: setting the CVar does not reliably hide already-visible CDM frames
    -- until the user toggles Blizzard's checkbox UI. If the profile explicitly disables
    -- CDM, we must proactively hide the viewer frames so the UI matches the setting
    -- immediately (including right after /reload).
    --
    -- We intentionally do NOT force-show when enabling; Edit Mode + viewer visibility
    -- settings (and Blizzard state) should remain the source of truth for whether a
    -- particular viewer is currently visible.
    if desired == false then
        local function hideViewers()
            local viewers = {
                "EssentialCooldownViewer",
                "UtilityCooldownViewer",
                "BuffIconCooldownViewer",
                "BuffBarCooldownViewer",
            }
            for _, viewerName in ipairs(viewers) do
                local frame = _G and _G[viewerName]
                if frame then
                    if frame.SetShown then
                        pcall(frame.SetShown, frame, false)
                    elseif frame.Hide then
                        pcall(frame.Hide, frame)
                    end
                end
            end
        end

        if InCombatLockdown and InCombatLockdown() then
            -- Avoid touching potentially protected UI during combat; retry once we leave combat.
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, function()
                    if not (InCombatLockdown and InCombatLockdown()) then
                        hideViewers()
                    end
                end)
            end
        else
            hideViewers()
        end
    end

    Debug("Applied cooldownViewerEnabled from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

local function ApplyPRDEnabledForActiveProfile(reason)
    local profile = addon and addon.db and addon.db.profile
    local s = profile and profile.prdSettings
    local desired = s and s.enablePRD
    if desired == nil then
        return  -- Not explicitly set; don't override CVar
    end
    local value = (desired and "1") or "0"

    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "nameplateShowSelf", value)
        elseif SetCVar then
            pcall(SetCVar, "nameplateShowSelf", value)
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            applyCVar()
        end)
    else
        applyCVar()
    end

    -- If disabling, trigger a re-apply so borders/overlays get cleared
    if desired == false then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if addon and addon.ApplyStyles then
                    addon:ApplyStyles()
                end
            end)
        end
    end

    Debug("Applied nameplateShowSelf from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

local function ApplyDamageMeterEnabledForActiveProfile(reason)
    local profile = addon and addon.db and addon.db.profile
    local s = profile and profile.damageMeterSettings
    local desired = s and s.enableDamageMeter
    if desired == nil then
        return  -- Not explicitly set; don't override CVar
    end
    local value = (desired and "1") or "0"

    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "damageMeterEnabled", value)
        elseif SetCVar then
            pcall(SetCVar, "damageMeterEnabled", value)
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            applyCVar()
        end)
    else
        applyCVar()
    end

    -- Hide damage meter if disabling (same pattern as CDM)
    if desired == false then
        local function hideDamageMeter()
            local frame = _G and _G["DamageMeter"]
            if frame then
                if frame.SetShown then
                    pcall(frame.SetShown, frame, false)
                elseif frame.Hide then
                    pcall(frame.Hide, frame)
                end
            end
        end

        if InCombatLockdown and InCombatLockdown() then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, function()
                    if not (InCombatLockdown and InCombatLockdown()) then
                        hideDamageMeter()
                    end
                end)
            end
        else
            hideDamageMeter()
        end
    end

    Debug("Applied damageMeterEnabled from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

local function ApplyActionBarsEnabledForActiveProfile(reason)
    local profile = addon and addon.db and addon.db.profile
    local s = profile and profile.actionBarSettings
    if not s then
        return  -- Zero-touch: no actionBarSettings subtable at all
    end

    local function applyBar(barNum)
        local key = "enableBar" .. barNum
        local desired = s[key]
        if desired == nil then
            return  -- Not explicitly set for this bar; don't override
        end

        local function applySettingsAPI()
            if not Settings or not Settings.GetSetting then return end
            local settingName = "PROXY_SHOW_ACTIONBAR_" .. barNum
            local ok, setting = pcall(Settings.GetSetting, settingName)
            if ok and setting and setting.SetValue then
                pcall(setting.SetValue, setting, desired)
            end
        end

        if InCombatLockdown and InCombatLockdown() then
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                applySettingsAPI()
            end)
        else
            applySettingsAPI()
        end
    end

    for barNum = 2, 8 do
        applyBar(barNum)
    end

    Debug("Applied actionBarSettings from profile", reason and ("reason=" .. tostring(reason)) or "")
end

local function getLayouts()
    if not C_EditMode or not C_EditMode.GetLayouts then return nil end
    return C_EditMode.GetLayouts()
end

function Profiles:FindLayoutIndex(layoutName)
    local data = getLayouts()
    if not data or not data.layouts then return nil end
    for index, layout in ipairs(data.layouts) do
        if layout.layoutName == layoutName then
            return index, layout
        end
    end
end

function Profiles:RestoreDropdownSelection(dropdown, key, displayText)
    if not dropdown then return end
    UIDropDownMenu_SetSelectedValue(dropdown, key)
    UIDropDownMenu_SetText(dropdown, displayText or key or "Select a layout")
end

local function addLayoutToCache(self, layoutName)
    if not layoutName then return end
    self._layoutLookup = self._layoutLookup or {}
    self._layoutLookup[layoutName] = true
    self._sortedEditableLayouts = self._sortedEditableLayouts or {}
    for _, existing in ipairs(self._sortedEditableLayouts) do
        if existing == layoutName then
            return
        end
    end
    table.insert(self._sortedEditableLayouts, layoutName)
    table.sort(self._sortedEditableLayouts, function(a, b)
        return tostring(a) < tostring(b)
    end)
end

local function getCurrentSpecID()
    if type(GetSpecialization) ~= "function" then
        return nil
    end
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end
    if type(GetSpecializationInfo) ~= "function" then
        return nil
    end
    local specID = select(1, GetSpecializationInfo(specIndex))
    return specID
end

-- Records the player's current spec so we can distinguish true mid-session spec changes
-- from incidental events (like PLAYER_ENTERING_WORLD during loading screens).
function Profiles:RecordCurrentSpec()
    local specID = getCurrentSpecID()
    if not specID then
        return
    end
    self._lastKnownSpecID = specID
end

local function buildDefaultProfile()
    -- Zero‑Touch policy: new profiles should start empty so Scoot does not
    -- implicitly "force defaults" into SavedVariables. AceDB defaults still exist
    -- via metatable fallback when reading unset keys.
    return {}
end

local function isCombatLocked()
    return InCombatLockdown and InCombatLockdown()
end

local function normalizeName(name)
    if type(name) ~= "string" then return nil end
    name = strtrim(name)
    if name == "" then return nil end
    return name
end

local function notifyUI()
    -- NOTE (2025-11-17): Layout/profile mutations no longer force a structural
    -- re-render of the Scoot settings list. The Profiles page is built to
    -- update its own rows and dropdowns in place, so we avoid calling
    -- RefreshCurrentCategoryDeferred here to prevent right-pane flicker.
end

-- Multi-pass sync after layout mutations to avoid stale lists
local function postMutationSync(self, reason)
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    self._postCopySuppressUntil = GetTime() + 0.3
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            if self and self.RefreshFromEditMode and ensureLayoutsLoaded() then
                self:RefreshFromEditMode(reason or "PostMutation")
            else
                self:RequestSync(reason or "PostMutation")
            end
        end)
        C_Timer.After(0.2, function()
            if self and self.RefreshFromEditMode and ensureLayoutsLoaded() then
                self:RefreshFromEditMode((reason or "PostMutation") .. "+retry")
            end
        end)
        -- After suppression window, attempt to apply any pending layout to EM
        C_Timer.After(0.35, function()
            if self and self.RefreshFromEditMode and ensureLayoutsLoaded() then
                self:RefreshFromEditMode((reason or "PostMutation") .. "+final")
            end
        end)
    end
end

-- clearDropdownTaint() REMOVED — dead code (defined but never called).

-- Copy all Edit Mode system settings (including anchors) from one layout to another
local function copyLayoutSettingsByName(sourceName, destName)
    if not sourceName or not destName then return false end
    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then return false end
    local li = C_EditMode.GetLayouts()
    if not li or not li.layouts then return false end
    local src, dst, dstIndex
    for idx, layout in ipairs(li.layouts) do
        if layout.layoutName == sourceName then src = layout end
        if layout.layoutName == destName then dst = layout; dstIndex = idx end
    end
    -- If source is a preset, fall back to preset manager
    if not src and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        for _, layout in ipairs(EditModePresetLayoutManager:GetCopyOfPresetLayouts() or {}) do
            if layout.layoutName == sourceName then src = layout break end
        end
    end
    if not (src and dst and dst.systems and src.systems) then return false end
    local function indexSystems(layout)
        local map = {}
        for _, sys in ipairs(layout.systems) do
            map[(sys.system or 0) .. ":" .. (sys.systemIndex or 0)] = sys
        end
        return map
    end
    local srcMap = indexSystems(src)
    for _, dsys in ipairs(dst.systems) do
        local key = (dsys.system or 0) .. ":" .. (dsys.systemIndex or 0)
        local ssys = srcMap[key]
        if ssys then
            -- Copy anchor and default-position flags
            if ssys.anchorInfo and dsys.anchorInfo then
                dsys.isInDefaultPosition = not not ssys.isInDefaultPosition
                local sa, da = ssys.anchorInfo, dsys.anchorInfo
                da.point = sa.point; da.relativePoint = sa.relativePoint
                da.offsetX = sa.offsetX; da.offsetY = sa.offsetY
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
    -- Ensure the destination is the active layout so the client reflects changes
    if li.activeLayout and li.layouts[li.activeLayout] and li.layouts[li.activeLayout].layoutName ~= destName then
        for idx, layout in ipairs(li.layouts) do
            if layout.layoutName == destName then li.activeLayout = idx break end
        end
    end
    C_EditMode.SaveLayouts(li)
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    return true
end

-- Apply the active profile's Edit Mode-backed settings for a single component
-- directly through the library, then persist with SaveOnly (no UI panel churn).
local function applyComponentEditModeViaLibrary(component)
    if not component or not component.frameName then return end
    local frame = _G[component.frameName]
    if not frame then return end
    if not LEO or not (LEO.IsReady and LEO:IsReady()) then return end
    if LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then if LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end end

    local EM = _G.Enum and _G.Enum.EditModeCooldownViewerSetting
    local function set(settingEnumOrId, value)
        if not settingEnumOrId or value == nil then return end
        pcall(LEO.SetFrameSetting, LEO, frame, settingEnumOrId, value)
    end

    local db = component.db or {}

    -- Position (anchor to CENTER with offsets from DB)
    do
        local x = tonumber(db.positionX or (component.settings.positionX and component.settings.positionX.default) or 0) or 0
        local y = tonumber(db.positionY or (component.settings.positionY and component.settings.positionY.default) or 0) or 0
        if LEO.ReanchorFrame and _G.UIParent then
            pcall(LEO.ReanchorFrame, LEO, frame, "CENTER", _G.UIParent, "CENTER", x, y)
        end
    end

    -- Orientation
    if component.settings.orientation then
        local v = (db.orientation or component.settings.orientation.default or "H")
        local emv = (v == "H") and 0 or 1
        set((EM and EM.Orientation) or 0, emv)
        -- UpdateSystemSetting* calls removed to prevent taint.
        -- Visual updates now come from the deferred SetActiveLayout() in SaveOnly().
    end

    -- Columns/Rows (IconLimit)
    if component.settings.columns then
        local v = tonumber(db.columns or component.settings.columns.default or 12) or 12
        set((EM and EM.IconLimit) or 1, v)
    end

    -- Direction (IconDirection)
    if component.settings.direction then
        local dir = tostring(db.direction or component.settings.direction.default or "right")
        local orientation = tostring(db.orientation or component.settings.orientation and component.settings.orientation.default or "H")
        local emv
        if orientation == "H" then emv = (dir == "right") and 1 or 0 else emv = (dir == "up") and 1 or 0 end
        set((EM and EM.IconDirection) or 2, emv)
    end

    -- Icon Padding
    if component.settings.iconPadding then
        local v = tonumber(db.iconPadding or component.settings.iconPadding.default or 2) or 2
        set((EM and EM.IconPadding) or 4, v)
    end

    -- Icon Size (Scale) - raw 50..200 snapped to 10s
    if component.settings.iconSize then
        local v = tonumber(db.iconSize or component.settings.iconSize.default or 100) or 100
        if v < 50 then v = 50 elseif v > 200 then v = 200 end
        v = math.floor(v / 10 + 0.5) * 10
        set((EM and EM.IconSize) or 3, v)
    end

    -- Tracked Bars: Display Mode (BarContent) 0=both,1=icon,2=name
    if component.id == "trackedBars" and component.settings.displayMode and _G.Enum and _G.Enum.EditModeCooldownViewerSetting then
        local v = tostring(db.displayMode or component.settings.displayMode.default or "both")
        local emv = (v == "icon") and 1 or ((v == "name") and 2 or 0)
        set(_G.Enum.EditModeCooldownViewerSetting.BarContent, emv)
    end

    -- Opacity 50..100
    if component.settings.opacity then
        local v = tonumber(db.opacity or component.settings.opacity.default or 100) or 100
        if v < 50 then v = 50 elseif v > 100 then v = 100 end
        set((EM and EM.Opacity) or 5, v)
    end

    -- Visibility dropdown (0 always, 1 combat, 2 hidden)
    if component.settings.visibilityMode then
        local mode = tostring(db.visibilityMode or component.settings.visibilityMode.default or "always")
        local emv = (mode == "combat") and 1 or ((mode == "never") and 2 or 0)
        if EM and EM.VisibleSetting then set(EM.VisibleSetting, emv) else set(0, emv) end
    end

    -- Checkboxes (timers/tooltips/hide-inactive) if present on component
    if component.settings.showTimer and EM and EM.ShowTimer then
        local v = (db.showTimer == nil and component.settings.showTimer.default) or db.showTimer
        set(EM.ShowTimer, v and 1 or 0)
    end
    if component.settings.showTooltip and EM and EM.ShowTooltips then
        local v = (db.showTooltip == nil and component.settings.showTooltip.default) or db.showTooltip
        set(EM.ShowTooltips, v and 1 or 0)
    end
    if component.settings.hideWhenInactive and EM then
        local v = (db.hideWhenInactive == nil and component.settings.hideWhenInactive.default) or db.hideWhenInactive
        -- No stable enum seen earlier; best-effort setting via library
        if frame.settingDisplayInfo and frame.settingDisplayInfo.hideWhenInactive then
            set(frame.settingDisplayInfo.hideWhenInactive, v and 1 or 0)
        end
    end

    -- NOTE: UpdateLayout() calls removed to prevent taint.
    -- The deferred SetActiveLayout() in SaveOnly() triggers Blizzard's clean rebuild.
end

local function applyAllComponentsEditModeViaLibrary()
    if not addon or not addon.Components then return end
    for _, component in pairs(addon.Components) do
        applyComponentEditModeViaLibrary(component)
    end
    if LEO and LEO.SaveOnly then pcall(LEO.SaveOnly, LEO) end
end

-- Short suppression window after copy/clone to avoid Edit Mode writes while opening the EM UI
function Profiles:IsPostCopySuppressed()
    local untilTs = self and self._postCopySuppressUntil
    if not untilTs then return false end
    local now = GetTime and GetTime() or 0
    return now > 0 and now < untilTs
end

local function buildPendingActivation(layoutName, meta)
    local p = { layoutName = layoutName }
    if type(meta) == "table" then
        for k, v in pairs(meta) do
            if k ~= "layoutName" then
                p[k] = v
            end
        end
    end
    return p
end

local function persistAceProfileKeyForChar(db, layoutName)
    if not (db and layoutName) then return end
    local sv = rawget(db, "sv")
    local charKey = db.keys and db.keys.char
    if sv and sv.profileKeys and charKey then
        sv.profileKeys[charKey] = layoutName
    end
end

local function persistEditModeActiveLayoutByName(layoutName)
    if not layoutName then return end
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts) then return end
    local li = C_EditMode.GetLayouts()
    if not (li and li.layouts) then return end
    for idx, layout in ipairs(li.layouts) do
        if layout and layout.layoutName == layoutName then
            li.activeLayout = idx
            break
        end
    end
    pcall(C_EditMode.SaveLayouts, li)
end

function Profiles:RequestReloadToProfile(layoutName, meta)
    -- IMPORTANT:
    -- ReloadUI() is a protected action and is not safe from arbitrary event handlers
    -- (e.g. spec-change, edit mode callbacks). Calling it directly can produce:
    --   [ADDON_ACTION_BLOCKED] AddOn 'Scoot' tried to call the protected function 'Reload()'.
    --
    -- All reloads MUST be initiated from a hardware event (typically a click).
    -- Therefore this API now delegates to PromptReloadToProfile().
    if not (self.db and self.db.global) then
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        -- Queue a safe prompt for when combat ends (handled by init.lua regen handler or callers).
        self._pendingReloadToProfile = { layoutName = layoutName, meta = meta }
        return true
    end
    return self:PromptReloadToProfile(layoutName, meta)
end

function Profiles:PromptReloadToProfile(layoutName, meta)
    if not (self.db and self.db.global) then
        return false
    end
    if not addon or not addon.Dialogs or not addon.Dialogs.Show then
        return false
    end
    -- Stash pending activation now; the actual ReloadUI() must come from a hardware event.
    self.db.global.pendingProfileActivation = buildPendingActivation(layoutName, meta)
    -- Choose appropriate dialog based on reason
    local dialogName = "SCOOT_PROFILE_RELOAD"
    if meta and meta.reason == "SpecChanged" then
        dialogName = "SCOOT_SPEC_PROFILE_RELOAD"
    end
    addon.Dialogs:Show(dialogName, {
        data = { layoutName = layoutName },
        onAccept = function()
            -- Persist selection right before reloading (hardware-event-safe click).
            -- Do this here so Cancel doesn't accidentally make the choice "stick" for next reload.
            if addon and addon.db then
                persistAceProfileKeyForChar(addon.db, layoutName)
            end
            persistEditModeActiveLayoutByName(layoutName)
            ReloadUI()
        end,
        onCancel = function()
            -- Abandon: clear pending activation so we don't surprise-reload on next load.
            if addon and addon.db and addon.db.global then
                addon.db.global.pendingProfileActivation = nil
            end
        end,
    })
    return true
end

function Profiles:DebugDumpLayouts(context)
    if not addon or not addon._dbgProfiles then return end
    if not C_EditMode or not C_EditMode.GetLayouts then return end
    local layoutData = C_EditMode.GetLayouts()
    if not layoutData or not layoutData.layouts then return end

    local lines = {}
    for index, layout in ipairs(layoutData.layouts) do
        local name = layout.layoutName or ("<unnamed " .. tostring(index) .. ">")
        local lType = LayoutTypeName(layout.layoutType)
        local modifier = layout.isPreset and "preset" or (layout.layoutType == Enum.EditModeLayoutType.Preset and "preset" or "custom")
        local dirty = layout.isModified and "modified" or "clean"
        lines[#lines + 1] = string.format("[%d] %s (%s, %s, %s)", index, name, lType, modifier, dirty)
    end

    local activeIndex = layoutData.activeLayout
    local activeLayout = layoutData.layouts[activeIndex]
    if activeLayout then
        Debug(string.format("Layouts(%s): active index=%d name=%s type=%s %s", context or "?", activeIndex or -1, tostring(activeLayout.layoutName), LayoutTypeName(activeLayout.layoutType), activeLayout.isModified and "modified" or "clean"))
    else
        Debug(string.format("Layouts(%s): active index=%s (missing entry)", context or "?", tostring(activeIndex)))
    end
    Debug("Layouts detail:", table.concat(lines, " | "))
end

function Profiles:Initialize()
    if self._initialized then
        return
    end

    if not addon or not addon.db then
        return
    end

    self.db = addon.db
    self._knownLayouts = {}
    self._layoutLookup = {}
    self._presetLookup = {}
    self._profileTemplate = buildDefaultProfile()
    self._pendingActiveLayout = nil
    self._pendingRefreshReason = "Initialize"
    self._lastPendingApply = 0
    self._lastRequestedLayout = nil
    self._pendingSpecReload = nil
    self._lastKnownSpecID = nil
    self._initialized = true
    Debug("Initialize")

    if self.db.RegisterCallback then
        self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
        self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileCopied")
        self.db.RegisterCallback(self, "OnProfileReset", "OnProfileReset")
        self.db.RegisterCallback(self, "OnProfileDeleted", "OnProfileDeleted")
        self.db.RegisterCallback(self, "OnNewProfile", "OnNewProfile")
    end

    -- Consume pending profile activation as early as possible (immediately after DB exists).
    -- This ensures that the very first post-reload session starts on the new profile/layout
    -- before any styling passes run, preventing "sticky" old-profile visuals.
    do
        local global = self.db and self.db.global
        local p = global and global.pendingProfileActivation
        if p and p.layoutName then
            local pendingCopy = p
            -- Switch immediately; if Edit Mode layouts aren't ready yet, SwitchToProfile will
            -- still set the AceDB profile and queue the layout apply for when layouts load.
            self:SwitchToProfile(p.layoutName, { reason = "PendingProfileActivation", force = true })
            global.pendingProfileActivation = nil
            -- Note: we intentionally do not print a chat message for spec-triggered reloads.
        end
    end

    -- Ensure CDM enable/disable is applied for the active profile on load.
    ApplyCooldownViewerEnabledForActiveProfile("Initialize")
    ApplyPRDEnabledForActiveProfile("Initialize")
    ApplyDamageMeterEnabledForActiveProfile("Initialize")
    ApplyActionBarsEnabledForActiveProfile("Initialize")
    if addon and addon.Chat and addon.Chat.ApplyFromProfile then
        addon.Chat:ApplyFromProfile("Profiles:Initialize")
    end

    self:RequestSync("Initialize")
end

function Profiles:OnNewProfile(_, profileKey)
    if not profileKey then
        return
    end
    self:EnsureProfileExists(profileKey)
end

function Profiles:OnProfileChanged(_, _, newProfileKey)
    if self._suppressProfileCallback then
        return
    end
    addon:LinkComponentsToDB()
    addon:ApplyStyles()
    ApplyCooldownViewerEnabledForActiveProfile("OnProfileChanged")
    ApplyPRDEnabledForActiveProfile("OnProfileChanged")
    ApplyDamageMeterEnabledForActiveProfile("OnProfileChanged")
    ApplyActionBarsEnabledForActiveProfile("OnProfileChanged")
    if addon and addon.Chat and addon.Chat.ApplyFromProfile then
        addon.Chat:ApplyFromProfile("Profiles:OnProfileChanged")
    end
    self._lastActiveLayout = newProfileKey
    self:RequestSync("ProfileChanged")
end

function Profiles:OnProfileCopied(_, _, sourceKey)
    addon:LinkComponentsToDB()
    addon:ApplyStyles()
    ApplyCooldownViewerEnabledForActiveProfile("OnProfileCopied")
    ApplyPRDEnabledForActiveProfile("OnProfileCopied")
    ApplyDamageMeterEnabledForActiveProfile("OnProfileCopied")
    ApplyActionBarsEnabledForActiveProfile("OnProfileCopied")
    if addon and addon.Chat and addon.Chat.ApplyFromProfile then
        addon.Chat:ApplyFromProfile("Profiles:OnProfileCopied")
    end
    self:RequestSync("ProfileCopied")
end

function Profiles:OnProfileReset()
    addon:LinkComponentsToDB()
    addon:ApplyStyles()
    ApplyCooldownViewerEnabledForActiveProfile("OnProfileReset")
    ApplyPRDEnabledForActiveProfile("OnProfileReset")
    ApplyDamageMeterEnabledForActiveProfile("OnProfileReset")
    ApplyActionBarsEnabledForActiveProfile("OnProfileReset")
    if addon and addon.Chat and addon.Chat.ApplyFromProfile then
        addon.Chat:ApplyFromProfile("Profiles:OnProfileReset")
    end
    self:RequestSync("ProfileReset")
end

function Profiles:OnProfileDeleted(_, _, profileKey)
    if profileKey and self._layoutLookup then
        self._layoutLookup[profileKey] = nil
    end
    self:RequestSync("ProfileDeleted")
end

function Profiles:IsReady()
    return self._initialized and ensureLayoutsLoaded()
end

function Profiles:RequestSync(reason)
    if ensureLayoutsLoaded() then
        self:RefreshFromEditMode(reason or "RequestSync")
        self._pendingRefreshReason = nil
        return
    end
    self._pendingRefreshReason = reason or self._pendingRefreshReason or "RequestSync"
end

function Profiles:TryPendingSync()
    if self._pendingRefreshReason and ensureLayoutsLoaded() then
        local reason = self._pendingRefreshReason
        self._pendingRefreshReason = nil
        self:RefreshFromEditMode(reason or "PendingSync")
    end
end

function Profiles:GetAvailableLayouts()
    local editable = {}
    local presets = {}
    for _, name in ipairs(self._sortedEditableLayouts or {}) do
        table.insert(editable, name)
    end
    for _, name in ipairs(self._sortedPresetLayouts or {}) do
        table.insert(presets, name)
    end
    return editable, presets
end

function Profiles:GetLayoutMenuEntries()
    local entries = {}
    local editable, presets = self:GetAvailableLayouts()

    for _, name in ipairs(editable) do
        table.insert(entries, {
            key = name,
            text = name,
            preset = false,
        })
    end

    for _, name in ipairs(presets) do
        table.insert(entries, {
            key = name,
            text = string.format("%s (Preset)", name),
            preset = true,
        })
    end

    return entries
end

function Profiles:IsPreset(profileKey)
    return self._presetLookup[profileKey] or false
end

function Profiles:EnsureProfileExists(profileKey, opts)
    if not profileKey or not self.db or not self.db.profiles then
        return
    end
    if self.db.profiles[profileKey] then
        if opts and opts.preset then
            self.db.profiles[profileKey].__preset = true
        end
        Debug("EnsureProfileExists reuse", profileKey, opts and opts.preset and "(preset)" or "")
        return
    end

    local template
    if opts and opts.copyFrom and self.db.profiles[opts.copyFrom] then
        template = deepCopy(self.db.profiles[opts.copyFrom])
    else
        template = deepCopy(self._profileTemplate)
    end

    if opts and opts.preset then
        template.__preset = true
    end

    self.db.profiles[profileKey] = template
    Debug("EnsureProfileExists created", profileKey, opts and opts.preset and "(preset)" or "", opts and opts.copyFrom and ("copy=" .. tostring(opts.copyFrom)) or "")
end

function Profiles:_setActiveProfile(profileKey, opts)
    if not profileKey or not self.db then
        return
    end
    opts = opts or {}
    local current = self.db:GetCurrentProfile()
    Debug("_setActiveProfile", profileKey, "current=" .. tostring(current), opts.skipLayout and "[skipLayout]" or "", opts.force and "[force]" or "")

    self:EnsureProfileExists(profileKey, { preset = self:IsPreset(profileKey) })

    -- Suppress SCT font change popup during profile switches
    addon._profileSwitchInProgress = true

    if current ~= profileKey or opts.force then
        self._suppressProfileCallback = true
        self.db:SetProfile(profileKey)
        self._suppressProfileCallback = false
    else
    end

    -- If switching to a truly empty/Zero‑Touch profile without reloading, clear
    -- frame-level enforcement flags so old-profile hooks stop forcing hidden states.
    do
        local profile = addon and addon.db and addon.db.profile
        local unitFrames = profile and rawget(profile, "unitFrames") or nil
        local components = profile and rawget(profile, "components") or nil
        local hasUF = type(unitFrames) == "table" and next(unitFrames) ~= nil
        local hasComponents = type(components) == "table" and next(components) ~= nil
        if (not hasUF) and (not hasComponents) and addon and addon.ClearFrameLevelState then
            addon:ClearFrameLevelState()
        end
    end

    addon:LinkComponentsToDB()
    addon:ApplyStyles()
    ApplyCooldownViewerEnabledForActiveProfile("_setActiveProfile")
    ApplyPRDEnabledForActiveProfile("_setActiveProfile")
    ApplyDamageMeterEnabledForActiveProfile("_setActiveProfile")
    ApplyActionBarsEnabledForActiveProfile("_setActiveProfile")
    if addon and addon.Chat and addon.Chat.ApplyFromProfile then
        addon.Chat:ApplyFromProfile("Profiles:_setActiveProfile")
    end

    -- Clear the suppression flag after profile switch completes
    addon._profileSwitchInProgress = false

    self._lastRequestedLayout = profileKey

    if not opts.skipLayout and ensureLayoutsLoaded() and self._layoutLookup[profileKey] then
        -- Suppress EM writes during the brief post-copy window to avoid blocked-action warnings
		if self:IsPostCopySuppressed() then
			self._pendingActiveLayout = profileKey
			Debug("_setActiveProfile suppressed EM write; pending set", profileKey)
			return
		end
		-- Ensure library state is current before switching layouts
		if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
		local names = (LEO and LEO.GetEditableLayoutNames and LEO:GetEditableLayoutNames()) or {}
		local found = false
		for _, n in ipairs(names) do if n == profileKey then found = true break end end
		if not found then
			self._pendingActiveLayout = profileKey
			Debug("Library missing target layout; deferring EM apply", profileKey)
			return
		end
		local active = LEO:GetActiveLayout()
        if active ~= profileKey then
            self._pendingActiveLayout = profileKey
            LEO:SetActiveLayout(profileKey)
            if addon.EditMode and addon.EditMode.SaveOnly then
                addon.EditMode.SaveOnly()
            end
            Debug("_setActiveProfile queued layout apply", profileKey, "previousActive=" .. tostring(active))
        else
            self._pendingActiveLayout = nil
            Debug("_setActiveProfile layout already active", profileKey)
        end
    end

    if addon and addon._dbgProfiles and C_Timer and C_Timer.After then
        local targetName = profileKey
        C_Timer.After(0.2, function()
            if addon and addon._dbgProfiles and LEO and LEO.GetActiveLayout then
                local nowActive = LEO:GetActiveLayout()
                Debug("Active layout after switch", "target=" .. tostring(targetName), "current=" .. tostring(nowActive))
            end
        end)
    end

    self._lastActiveLayout = profileKey
end

function Profiles:SwitchToProfile(profileKey, opts)
    if not profileKey then
        return
    end
    opts = opts or {}
    Debug("SwitchToProfile", profileKey, opts.reason and ("reason=" .. tostring(opts.reason)) or "", opts.skipLayout and "[skipLayout]" or "")

    -- Avoid reload loops / unnecessary reloads:
    -- - PendingProfileActivation is consumed on load; we must switch immediately without reloading.
    -- - PresetActivationOnLoad similarly must not trigger another reload.
    local skipReload = opts.skipReload
        or opts.reason == "PendingProfileActivation"
        or opts.reason == "PresetActivationOnLoad"
        or opts.reason == "Initialize"

    -- If this is a genuine switch (different profile) and we're not in a safe on-load path,
    -- force a reload so Blizzard can reinitialize baselines correctly.
    if not skipReload and self.db and self.db.GetCurrentProfile then
        local current = self.db:GetCurrentProfile()
        if current ~= profileKey then
            if isCombatLocked() then
                if addon and addon.Print then addon:Print("Cannot switch profiles during combat.") end
                return
            end
            -- Carry a small amount of metadata for debugging/UX on next load
            local pendingMeta = opts.pendingMeta or { reason = opts.reason }
            -- ReloadUI() is protected unless triggered by a hardware event (e.g. a click).
            -- SwitchToProfile can be reached from non-hardware events, so we must prompt.
            self:PromptReloadToProfile(profileKey, pendingMeta)
            return
        end
    end

    if not ensureLayoutsLoaded() then
        self:EnsureProfileExists(profileKey)
        self.db:SetProfile(profileKey)
        addon:LinkComponentsToDB()
        addon:ApplyStyles()
        self._pendingActiveLayout = profileKey
        self._pendingRefreshReason = "DeferredSwitch"
        Debug("SwitchToProfile deferred pending sync", profileKey)
        return
    end
    if not self._layoutLookup[profileKey] then
        -- Allow switching to existing AceDB profile even if layout is missing,
        -- but do not attempt to adjust Edit Mode.
        opts.skipLayout = true
        Debug("SwitchToProfile missing layout lookup entry, skipping EM interaction", profileKey)
    end
    self:_setActiveProfile(profileKey, opts)
    self:PruneSpecAssignments()
end

function Profiles:RefreshFromEditMode(origin)
    if not ensureLayoutsLoaded() then
        Debug("RefreshFromEditMode aborted layouts not ready", origin or "?")
        return
    end

    local editableLayouts = LEO:GetEditableLayoutNames() or {}
    local presetLayouts = LEO:GetPresetLayoutNames() or {}
    local activeLayout = LEO:GetActiveLayout()
    Debug("RefreshFromEditMode", origin or "?", "active=" .. tostring(activeLayout), "pending=" .. tostring(self._pendingActiveLayout))

    table.sort(editableLayouts, function(a, b) return tostring(a) < tostring(b) end)
    table.sort(presetLayouts, function(a, b) return tostring(a) < tostring(b) end)

    wipe(self._layoutLookup)
    wipe(self._presetLookup)

    self._sortedEditableLayouts = {}
    self._sortedPresetLayouts = {}

    for _, name in ipairs(editableLayouts) do
        self._layoutLookup[name] = true
        table.insert(self._sortedEditableLayouts, name)
        self:EnsureProfileExists(name, { copyFrom = self._lastActiveLayout })
    end

    for _, name in ipairs(presetLayouts) do
        self._layoutLookup[name] = true
        self._presetLookup[name] = true
        table.insert(self._sortedPresetLayouts, name)
        self:EnsureProfileExists(name, { preset = true })
    end

    -- Auto-heal: if AceDB contains profiles that don't exist as layouts, remove them
    -- so they can't block preset creation or cause cross-machine desync confusion.
    self:CleanupOrphanedProfiles()

    -- Detect if the current profile's Edit Mode layout was deleted externally (via Blizzard's Edit Mode UI).
    -- If so, prompt the user to reload so state can be properly synchronized.
    self:CheckForExternalDeletion()

    self:PruneSpecAssignments()
    if addon and addon._dbgProfiles then
        Debug("Editable:" , table.concat(self._sortedEditableLayouts, ", "))
        Debug("Presets:" , table.concat(self._sortedPresetLayouts, ", "))
    end

    self:DebugDumpLayouts(origin or "Refresh")

    local pending = self._pendingActiveLayout
    if pending and not self._layoutLookup[pending] then
        self._pendingActiveLayout = nil
        pending = nil
        Debug("Pending layout cleared; no lookup entry")
    end
    local currentProfile = self.db:GetCurrentProfile()
    Debug("Refresh state", "profile=" .. tostring(currentProfile), "active=" .. tostring(activeLayout), "pending=" .. tostring(pending))
    if pending and self._layoutLookup[pending] and activeLayout ~= pending then
        if currentProfile ~= pending then
            self:_setActiveProfile(pending, { skipLayout = true, force = true })
            Debug("Applied pending profile while awaiting EM", pending)
        end
        local now = GetTime and GetTime() or 0
        if not self:IsPostCopySuppressed() and (now == 0 or (now - (self._lastPendingApply or 0)) > 0.5) then
            if LEO and LEO.SetActiveLayout then
                pcall(LEO.SetActiveLayout, LEO, pending)
            end
            if addon.EditMode and addon.EditMode.SaveOnly then
                addon.EditMode.SaveOnly()
            end
            self._lastPendingApply = now
            Debug("Re-applied pending layout to Edit Mode", pending)
        else
            Debug("Suppressed EM re-apply during post-copy window", pending)
        end
        return
    end

    if activeLayout and self._layoutLookup[activeLayout] then
        local options = { skipLayout = true }
        if self._pendingActiveLayout and self._pendingActiveLayout ~= activeLayout then
            options.skipLayout = self:IsPostCopySuppressed() and true or false
            options.force = true
        end
        self:_setActiveProfile(activeLayout, options)
        Debug("Synced active layout from Edit Mode", activeLayout)
    else
        local current = self.db:GetCurrentProfile()
        if current and self._layoutLookup[current] then
            if activeLayout ~= current then
                self:_setActiveProfile(current, { force = true })
                Debug("Forced Edit Mode to current profile", current, "was", tostring(activeLayout))
            end
        elseif self._sortedEditableLayouts[1] then
            self:SwitchToProfile(self._sortedEditableLayouts[1], { force = true })
            Debug("Fallback to first editable layout", self._sortedEditableLayouts[1])
        end
    end

    if activeLayout and self._pendingActiveLayout == activeLayout then
        self._pendingActiveLayout = nil
        Debug("Cleared pending flag; layout now active", activeLayout)
    end
end

function Profiles:GetActiveProfile()
    return self.db and self.db:GetCurrentProfile()
end

function Profiles:IsActiveProfilePreset()
    local active = self:GetActiveProfile()
    if not active then
        return false
    end
    return self:IsPreset(active)
end

-- Expose internals for sibling profiles files
addon.Profiles._Debug = Debug
addon.Profiles._deepCopy = deepCopy
addon.Profiles._ensureLayoutsLoaded = ensureLayoutsLoaded
addon.Profiles._isCombatLocked = isCombatLocked
addon.Profiles._normalizeName = normalizeName
addon.Profiles._notifyUI = notifyUI
addon.Profiles._postMutationSync = postMutationSync
addon.Profiles._addLayoutToCache = addLayoutToCache
addon.Profiles._getCurrentSpecID = getCurrentSpecID

return Profiles
