-- settingspanel/navigation.lua - Back-sync, content cleanup, copy-from, nav handler, titles
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls
local Navigation = addon.UI.Navigation
local SettingsBuilder = addon.UI.SettingsBuilder

-- Import promoted constants from ascii.lua and core.lua
local ASCII_LOGO = UIPanel._ASCII_LOGO
local CONTENT_PADDING = UIPanel._CONTENT_PADDING

-- Edit Mode Back-Sync Handler
-- Marks affected component for refresh and triggers re-render if visible.

function UIPanel:HandleEditModeBackSync(componentId, settingId)
    if not componentId then return end

    self._pendingBackSync[componentId] = true

    local categoryKey = componentId

    -- Map individual action bar IDs to consolidated nav key
    if componentId:match("^actionBar[1-8]$") then
        categoryKey = "actionBars18"
    end

    if self._currentCategoryKey == categoryKey then
        C_Timer.After(0, function()
            if self.frame and self.frame:IsShown() then
                self:OnNavigationSelect(categoryKey, categoryKey)
            end
        end)
    end
end

function UIPanel:CheckPendingBackSync(componentId)
    if self._pendingBackSync[componentId] then
        self._pendingBackSync[componentId] = nil
        return true
    end
    return false
end

function UIPanel:ClearPendingBackSync()
    wipe(self._pendingBackSync)
end

-- Content Cleanup System
-- Cleans up all content types before rendering a new section.
-- New sections with custom state tracking must add their cleanup logic here.

-- The header subtitle is one shared FontString. Pages that restyle it (the
-- Aura List hangs a gray, wrapped how-to line under the title) put it back
-- through this before another page reuses it: single bottom-left anchor,
-- 11pt, accent at half alpha, wrap on (the stock look from CreateContentPane).
function UIPanel:ResetHeaderSubtitle()
    local contentPane = self.frame and self.frame._contentPane
    local sub = contentPane and contentPane._headerSubtitle
    if not sub or not contentPane._header then return end
    sub:ClearAllPoints()
    sub:SetPoint("BOTTOMLEFT", contentPane._header, "BOTTOMLEFT", 16, 8)
    sub:SetFont(Theme:GetFont("LABEL"), 11, "")
    sub:SetJustifyH("LEFT")
    sub:SetJustifyV("MIDDLE")
    sub:SetWordWrap(true)
    local sr, sg, sb = Theme:GetAccentColor()
    sub:SetTextColor(sr, sg, sb, 0.5)
    contentPane._headerSubtitleCustom = nil
end

function UIPanel:ClearContent()
    -- Features page cleanup (restore scroll frame, hide reload area, destroy rows)
    if self._startHereCleanup then
        self._startHereCleanup()
    end

    -- Aura List page cleanup (two-pane layout, hand-rolled rows)
    if self._scootAurasCleanup then
        self._scootAurasCleanup()
    end

    -- Builder-based content
    if self._currentBuilder then
        self._currentBuilder:Cleanup()
        self._currentBuilder = nil
    end

    -- Rules state-based content
    if self._rulesState and self._rulesState.currentControls then
        for _, control in ipairs(self._rulesState.currentControls) do
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
        self._rulesState.currentControls = {}
    end

    -- Profiles > Manage Profiles state-based content
    if self._profilesManageState and self._profilesManageState.currentControls then
        for _, control in ipairs(self._profilesManageState.currentControls) do
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
        self._profilesManageState.currentControls = {}
    end

    -- Profiles > Presets state-based content
    if self._presetsState and self._presetsState.currentControls then
        for _, control in ipairs(self._presetsState.currentControls) do
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
        self._presetsState.currentControls = {}
    end

    -- Profiles > Import/Export state-based content
    if self._importExportState and self._importExportState.currentControls then
        for _, control in ipairs(self._importExportState.currentControls) do
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
        self._importExportState.currentControls = {}
    end

    -- Apply All > Fonts state-based content
    if self._applyAllFontsControls then
        for _, control in ipairs(self._applyAllFontsControls) do
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
        self._applyAllFontsControls = {}
    end

    -- Apply All > Bar Textures state-based content
    if self._applyAllTexturesControls then
        for _, control in ipairs(self._applyAllTexturesControls) do
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
        self._applyAllTexturesControls = {}
    end

    -- Debug Menu state-based content
    if self._debugMenuControls then
        for _, control in ipairs(self._debugMenuControls) do
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
        self._debugMenuControls = {}
    end

    -- Search page cleanup
    if self._searchCleanup then
        self._searchCleanup()
    end
end

-- Collapse All Sections

function UIPanel:CollapseAllSections()
    local key = self._currentCategoryKey
    if not key then return end

    -- Resolve consolidated action bar key to selected bar's componentId
    local componentId = key
    if key == "actionBars18" then
        componentId = self._actionBarSelectedBar or "actionBar1"
    end

    local sectionStates = addon.UI._sectionStates
    if sectionStates and sectionStates[componentId] then
        for sectionKey in pairs(sectionStates[componentId]) do
            sectionStates[componentId][sectionKey] = false
        end
    end

    self:OnNavigationSelect(key, key)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
end

-- Update Collapse All Button Visibility

function UIPanel:UpdateCollapseAllButton()
    local frame = self.frame
    if not frame or not frame._contentPane then return end

    local contentPane = frame._contentPane
    local collapseBtn = contentPane._collapseAllBtn
    if not collapseBtn then return end

    local hasCollapsible = false
    if self._currentBuilder and self._currentBuilder._controls then
        for _, control in ipairs(self._currentBuilder._controls) do
            if control._componentId and control._sectionKey then
                hasCollapsible = true
                break
            end
        end
    end

    if hasCollapsible then
        collapseBtn:Show()
    else
        collapseBtn:Hide()
    end
end

-- Copy From Dropdown Management

local ACTION_BAR_COPY_TARGETS = {
    actionBar1 = true,
    actionBar2 = true,
    actionBar3 = true,
    actionBar4 = true,
    actionBar5 = true,
    actionBar6 = true,
    actionBar7 = true,
    actionBar8 = true,
    petBar = true,  -- Can only be a destination, not a source
}

local ACTION_BAR_NAMES = {
    actionBar1 = "Action Bar 1",
    actionBar2 = "Action Bar 2",
    actionBar3 = "Action Bar 3",
    actionBar4 = "Action Bar 4",
    actionBar5 = "Action Bar 5",
    actionBar6 = "Action Bar 6",
    actionBar7 = "Action Bar 7",
    actionBar8 = "Action Bar 8",
}

local ACTION_BAR_ORDER = {
    "actionBar1", "actionBar2", "actionBar3", "actionBar4",
    "actionBar5", "actionBar6", "actionBar7", "actionBar8",
}

local UNIT_FRAME_COPY_TARGETS = {
    ufPlayer = true,
    ufTarget = true,
    ufFocus = true,
    ufPet = true,
    ufToT = true,
    ufFocusTarget = true,
    -- ufBoss excluded (no copy support)
}

local UNIT_FRAME_NAMES = {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus = "Focus",
    ufPet = "Pet",
    ufToT = "Target of Target",
    ufFocusTarget = "Target of Focus",
}

local UNIT_FRAME_KEYS = {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus = "Focus",
    ufPet = "Pet",
    ufToT = "TargetOfTarget",
    ufFocusTarget = "FocusTarget",
}

local FULL_UNIT_FRAME_ORDER = { "ufPlayer", "ufTarget", "ufFocus", "ufPet" }

local TOT_FOT_SOURCES = {
    ufToT = { "ufFocusTarget" },
    ufFocusTarget = { "ufToT" },
}

-- Unit Frames Z: a separate copy type -- the X and Z settings schemas share
-- nothing, so Z pages only ever offer Z sources. Future Z units join these
-- tables.
local UFZ_COPY_TARGETS = {
    ufzPlayer = true,
    ufzTarget = true,
    ufzBoss = true,
}

local UFZ_NAMES = {
    ufzPlayer = "Player Frame Z",
    ufzTarget = "Target Frame Z",
    ufzBoss = "Boss Frames Z",
}

-- The CONFIG key, which for Boss is one key behind five frames -- the copy
-- lands on all of them because it goes through the shared config table.
local UFZ_KEYS = {
    ufzPlayer = "Player",
    ufzTarget = "Target",
    ufzBoss = "Boss",
}

local UFZ_ORDER = { "ufzPlayer", "ufzTarget", "ufzBoss" }

local CUSTOM_GROUP_COPY_TARGETS = {
    customGroup1 = true,
    customGroup2 = true,
    customGroup3 = true,
    customGroup4 = true,
    customGroup5 = true,
}

local CUSTOM_GROUP_STATIC_NAMES = {
    essentialCooldowns = "Essential Cooldowns",
    utilityCooldowns = "Utility Cooldowns",
}

local function GetCopySourceName(key)
    local i = key and key:match("^customGroup(%d)$")
    if i then
        local CG = addon.CustomGroups
        if CG and CG.GetGroupDisplayName then
            return CG.GetGroupDisplayName(tonumber(i))
        end
        return "Custom Group " .. i
    end
    return CUSTOM_GROUP_STATIC_NAMES[key] or key
end

local CUSTOM_GROUP_SOURCE_ORDER = {
    "customGroup1", "customGroup2", "customGroup3",
    "customGroup4", "customGroup5",
    "essentialCooldowns", "utilityCooldowns",
}

function UIPanel:UpdateCopyFromDropdown()
    local frame = self.frame
    if not frame or not frame._contentPane then return end

    local contentPane = frame._contentPane
    local dropdown = contentPane._copyFromDropdown
    local label = contentPane._copyFromLabel
    if not dropdown then return end

    local key = self._currentCategoryKey

    -- Resolve consolidated action bar key to selected bar
    local effectiveKey = key
    if key == "actionBars18" then
        effectiveKey = self._actionBarSelectedBar or "actionBar1"
    end

    -- Check if this is an Action Bar category
    if effectiveKey and ACTION_BAR_COPY_TARGETS[effectiveKey] then
        local values = {}
        local order = {}
        for _, barKey in ipairs(ACTION_BAR_ORDER) do
            if barKey ~= effectiveKey then
                values[barKey] = ACTION_BAR_NAMES[barKey]
                table.insert(order, barKey)
            end
        end

        dropdown:SetOptions(values, order)
        dropdown:ClearSelection()
        dropdown:Show()
        if label then label:Show() end

    -- Check if this is a Unit Frame category
    elseif key and UNIT_FRAME_COPY_TARGETS[key] then
        local values = {}
        local order = {}

        if TOT_FOT_SOURCES[key] then
            for _, sourceKey in ipairs(TOT_FOT_SOURCES[key]) do
                values[sourceKey] = UNIT_FRAME_NAMES[sourceKey]
                table.insert(order, sourceKey)
            end
        else
            for _, ufKey in ipairs(FULL_UNIT_FRAME_ORDER) do
                if ufKey ~= key then
                    values[ufKey] = UNIT_FRAME_NAMES[ufKey]
                    table.insert(order, ufKey)
                end
            end
        end

        dropdown:SetOptions(values, order)
        dropdown:ClearSelection()
        dropdown:Show()
        if label then label:Show() end

    -- Check if this is a Unit Frame Z category
    elseif key and UFZ_COPY_TARGETS[key] then
        local values = {}
        local order = {}
        for _, ufzKey in ipairs(UFZ_ORDER) do
            if ufzKey ~= key then
                values[ufzKey] = UFZ_NAMES[ufzKey]
                table.insert(order, ufzKey)
            end
        end

        dropdown:SetOptions(values, order)
        dropdown:ClearSelection()
        dropdown:Show()
        if label then label:Show() end

    -- Check if this is a Custom Group category
    elseif key and CUSTOM_GROUP_COPY_TARGETS[key] then
        local values = {}
        local order = {}
        for _, sourceKey in ipairs(CUSTOM_GROUP_SOURCE_ORDER) do
            if sourceKey ~= key then
                values[sourceKey] = GetCopySourceName(sourceKey)
                table.insert(order, sourceKey)
            end
        end

        dropdown:SetOptions(values, order)
        dropdown:ClearSelection()
        dropdown:Show()
        if label then label:Show() end
    else
        dropdown:Hide()
        if label then label:Hide() end
    end
end

function UIPanel:HandleCopyFrom(sourceKey)
    local destKey = self._currentCategoryKey
    if not sourceKey or not destKey then return end

    -- Resolve consolidated action bar key to selected bar
    if destKey == "actionBars18" then
        destKey = self._actionBarSelectedBar or "actionBar1"
    end

    local isActionBar = ACTION_BAR_COPY_TARGETS[destKey]
    local isUnitFrame = UNIT_FRAME_COPY_TARGETS[destKey]
    local isCustomGroup = CUSTOM_GROUP_COPY_TARGETS[destKey]
    local isUFZ = UFZ_COPY_TARGETS[destKey]

    local sourceName, destName

    if isActionBar then
        sourceName = ACTION_BAR_NAMES[sourceKey] or sourceKey
        destName = ACTION_BAR_NAMES[destKey] or self:GetCategoryTitle(destKey)
    elseif isUnitFrame then
        sourceName = UNIT_FRAME_NAMES[sourceKey] or sourceKey
        destName = UNIT_FRAME_NAMES[destKey] or self:GetCategoryTitle(destKey)
    elseif isUFZ then
        sourceName = UFZ_NAMES[sourceKey] or sourceKey
        destName = UFZ_NAMES[destKey] or self:GetCategoryTitle(destKey)
    elseif isCustomGroup then
        sourceName = GetCopySourceName(sourceKey)
        destName = GetCopySourceName(destKey)
    else
        return
    end

    if addon.Dialogs and addon.Dialogs.Show then
        local panel = self
        local dialogKey = (isUnitFrame or isUFZ) and "SCOOT_COPY_UF_CONFIRM"
                       or isCustomGroup and "SCOOT_COPY_CUSTOMGROUP_CONFIRM"
                       or "SCOOT_COPY_ACTIONBAR_CONFIRM"
        addon.Dialogs:Show(dialogKey, {
            formatArgs = { sourceName, destName },
            data = {
                sourceId = sourceKey,
                destId = destKey,
                sourceName = sourceName,
                destName = destName,
                isUnitFrame = isUnitFrame,
                isCustomGroup = isCustomGroup,
                isUFZ = isUFZ,
            },
            onAccept = function()
                panel:ExecuteCopyFrom(sourceKey, destKey, isUnitFrame, isCustomGroup, isUFZ)
            end,
        })
    else
        -- Fallback if dialogs not loaded
        self:ExecuteCopyFrom(sourceKey, destKey, isUnitFrame, isCustomGroup, isUFZ)
    end
end

function UIPanel:ExecuteCopyFrom(sourceKey, destKey, isUnitFrame, isCustomGroup, isUFZ)
    if isUnitFrame then
        if addon and addon.CopyUnitFrameSettings then
            local sourceUnit = UNIT_FRAME_KEYS[sourceKey]
            local destUnit = UNIT_FRAME_KEYS[destKey]
            local ok, err = addon.CopyUnitFrameSettings(sourceUnit, destUnit)

            if ok then
                C_Timer.After(0.1, function()
                    local panel = addon.UI and addon.UI.SettingsPanel
                    if panel and panel._currentCategoryKey == destKey then
                        panel:OnNavigationSelect(destKey, destKey)
                    end
                end)
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            else
                if addon.Dialogs and addon.Dialogs.Show then
                    addon.Dialogs:Show("SCOOT_COPY_UF_ERROR", {
                        formatArgs = { err or "Unknown error" },
                    })
                elseif addon.Print then
                    addon:Print("Copy failed: " .. (err or "unknown error"))
                end
            end
        end
    elseif isUFZ then
        if addon and addon.CopyUnitFrameZSettings then
            local sourceUnit = UFZ_KEYS[sourceKey]
            local destUnit = UFZ_KEYS[destKey]
            if addon.CopyUnitFrameZSettings(sourceUnit, destUnit) then
                C_Timer.After(0.1, function()
                    local panel = addon.UI and addon.UI.SettingsPanel
                    if panel and panel._currentCategoryKey == destKey then
                        panel:OnNavigationSelect(destKey, destKey)
                    end
                end)
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end
        end
    elseif isCustomGroup then
        if addon and addon.CopyCDMCustomGroupSettings then
            addon.CopyCDMCustomGroupSettings(sourceKey, destKey)

            C_Timer.After(0.1, function()
                local panel = addon.UI and addon.UI.SettingsPanel
                if panel and panel._currentCategoryKey == destKey then
                    panel:OnNavigationSelect(destKey, destKey)
                end
            end)

            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    else
        if addon and addon.CopyActionBarSettings then
            addon.CopyActionBarSettings(sourceKey, destKey)

            C_Timer.After(0.1, function()
                local panel = addon.UI and addon.UI.SettingsPanel
                if panel then
                    -- Re-render consolidated page or individual bar page
                    local navKey = panel._currentCategoryKey
                    if navKey == "actionBars18" or navKey == destKey then
                        panel:OnNavigationSelect(navKey, navKey)
                    end
                end
            end)

            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    end
end

-- Defaults Reset Map
-- Maps nav keys to their reset strategy. Categories NOT listed get no Defaults button.

local DEFAULTS_RESET_MAP = {
    -- CDM components
    essentialCooldowns  = { strategy = "component", id = "essentialCooldowns" },
    utilityCooldowns    = { strategy = "component", id = "utilityCooldowns" },
    trackedBuffs        = { strategy = "component", id = "trackedBuffs" },
    trackedBars         = { strategy = "component", id = "trackedBars" },
    customGroup1        = { strategy = "component", id = "customGroup1" },
    customGroup2        = { strategy = "component", id = "customGroup2" },
    customGroup3        = { strategy = "component", id = "customGroup3" },
    customGroup4        = { strategy = "component", id = "customGroup4" },
    customGroup5        = { strategy = "component", id = "customGroup5" },
    -- Action Bars (consolidated)
    actionBars18        = { strategy = "actionBarSelected" },
    petBar              = { strategy = "component", id = "petBar" },
    stanceBar           = { strategy = "component", id = "stanceBar" },
    microBar            = { strategy = "component", id = "microBar" },
    extraAbilities      = { strategy = "component", id = "extraAbilities" },
    -- Buffs/Debuffs
    buffs               = { strategy = "component", id = "buffs" },
    debuffs             = { strategy = "component", id = "debuffs" },
    -- Interface
    tooltip             = { strategy = "component", id = "tooltip" },
    objectiveTracker    = { strategy = "component", id = "objectiveTracker" },
    damageMeter         = { strategy = "component", id = "damageMeter" },
    minimap             = { strategy = "component", id = "minimapStyle" },
    chat                = { strategy = "profileData", dataKey = "chat" },
    -- SCT
    sctDamage           = { strategy = "component", id = "sctDamage" },
    -- Personal Resource Display
    prdGeneral          = { strategy = "component", id = "prdGlobal" },
    prdHealthBar        = { strategy = "component", id = "prdHealth" },
    prdPowerBar         = { strategy = "component", id = "prdPower" },
    prdClassResource    = { strategy = "component", id = "prdClassResource" },
    -- Unit Frames
    ufPlayer            = { strategy = "unitFrame", unitKey = "Player" },
    ufTarget            = { strategy = "unitFrame", unitKey = "Target" },
    ufFocus             = { strategy = "unitFrame", unitKey = "Focus" },
    ufPet               = { strategy = "unitFrame", unitKey = "Pet" },
    ufToT               = { strategy = "unitFrame", unitKey = "TargetOfTarget" },
    ufFocusTarget       = { strategy = "unitFrame", unitKey = "FocusTarget" },
    ufBoss              = { strategy = "unitFrame", unitKey = "Boss" },
    -- Group Frames
    gfParty             = { strategy = "groupFrame", subKey = "party" },
    gfRaid              = { strategy = "groupFrame", subKey = "raid" },
    -- Class Auras
    classAurasDeathKnight = { strategy = "classAuras", classToken = "DEATHKNIGHT" },
    classAurasDemonHunter = { strategy = "classAuras", classToken = "DEMONHUNTER" },
    classAurasDruid       = { strategy = "classAuras", classToken = "DRUID" },
    classAurasEvoker      = { strategy = "classAuras", classToken = "EVOKER" },
    classAurasHunter      = { strategy = "classAuras", classToken = "HUNTER" },
    classAurasMage        = { strategy = "classAuras", classToken = "MAGE" },
    classAurasMonk        = { strategy = "classAuras", classToken = "MONK" },
    classAurasPaladin     = { strategy = "classAuras", classToken = "PALADIN" },
    classAurasPriest      = { strategy = "classAuras", classToken = "PRIEST" },
    classAurasRogue       = { strategy = "classAuras", classToken = "ROGUE" },
    classAurasShaman      = { strategy = "classAuras", classToken = "SHAMAN" },
    classAurasWarlock     = { strategy = "classAuras", classToken = "WARLOCK" },
    classAurasWarrior     = { strategy = "classAuras", classToken = "WARRIOR" },
}

-- Update Defaults Button Visibility & Anchoring

function UIPanel:UpdateDefaultsButton()
    local frame = self.frame
    if not frame or not frame._contentPane then return end

    local contentPane = frame._contentPane
    local defaultsBtn = contentPane._defaultsBtn
    local defaultsInfoIcon = contentPane._defaultsInfoIcon
    if not defaultsBtn then return end

    local key = self._currentCategoryKey
    local resetInfo = key and DEFAULTS_RESET_MAP[key]

    if not resetInfo then
        defaultsBtn:Hide()
        if defaultsInfoIcon then defaultsInfoIcon:Hide() end
        return
    end

    -- Determine anchor based on subtitle visibility
    defaultsBtn:ClearAllPoints()
    local subtitle = contentPane._headerSubtitle
    if subtitle and subtitle:IsShown() then
        defaultsBtn:SetPoint("LEFT", subtitle, "RIGHT", 12, 0)
    else
        defaultsBtn:SetPoint("BOTTOMLEFT", contentPane._header, "BOTTOMLEFT", 16, 8)
    end
    defaultsBtn:Show()

    if defaultsInfoIcon then
        defaultsInfoIcon:ClearAllPoints()
        defaultsInfoIcon:SetPoint("LEFT", defaultsBtn, "RIGHT", 6, 0)
        defaultsInfoIcon:Show()
    end
end

-- Handle Defaults Button Click

function UIPanel:HandleDefaultsClick()
    if InCombatLockdown() then return end

    local key = self._currentCategoryKey
    if not key then return end

    local resetInfo = DEFAULTS_RESET_MAP[key]
    if not resetInfo then return end

    -- Resolve consolidated action bar to selected bar
    local resolvedResetInfo = resetInfo
    local categoryTitle
    if resetInfo.strategy == "actionBarSelected" then
        local selectedBar = self._actionBarSelectedBar or "actionBar1"
        resolvedResetInfo = { strategy = "component", id = selectedBar }
        categoryTitle = ACTION_BAR_NAMES[selectedBar] or selectedBar
    else
        categoryTitle = self:GetCategoryTitle(key)
    end

    local panel = self

    if addon.Dialogs and addon.Dialogs.Show then
        addon.Dialogs:Show("SCOOT_RESET_DEFAULTS", {
            formatArgs = { categoryTitle },
            onAccept = function()
                panel:ExecuteDefaultsReset(key, resolvedResetInfo)
            end,
        })
    end
end

-- Execute Defaults Reset

function UIPanel:ExecuteDefaultsReset(key, resetInfo)
    local profile = addon.db and addon.db.profile
    if not profile then return end

    local strategy = resetInfo.strategy

    if strategy == "component" then
        if profile.components then
            profile.components[resetInfo.id] = nil
        end

    elseif strategy == "unitFrame" then
        if profile.unitFrames then
            profile.unitFrames[resetInfo.unitKey] = nil
        end

    elseif strategy == "groupFrame" then
        if profile.groupFrames then
            profile.groupFrames[resetInfo.subKey] = nil
        end

    elseif strategy == "classAuras" then
        local CA = addon.ClassAuras
        if CA and CA.GetClassAuras then
            local auras = CA.GetClassAuras(resetInfo.classToken)
            for _, aura in ipairs(auras) do
                if profile.components then
                    profile.components["classAura_" .. aura.id] = nil
                end
                if profile.classAuraPositions then
                    profile.classAuraPositions[aura.id] = nil
                end
            end
        end

    elseif strategy == "profileData" then
        profile[resetInfo.dataKey] = nil
    end

    ReloadUI()
end

-- Navigation Selection Handler

function UIPanel:OnNavigationSelect(key, previousKey)
    -- Navigation guard: Features page may require reload confirmation
    if self._navigationGuard then
        local guard = self._navigationGuard
        guard(key, function()
            self:OnNavigationSelect(key, previousKey)
        end)
        return
    end

    local frame = self.frame
    if not frame or not frame._contentPane then return end

    local contentPane = frame._contentPane
    local scrollContent = contentPane._scrollContent
    local isHome = (key == "home" or key == nil)
    local wasHome = (previousKey == "home" or previousKey == nil)

    self._currentCategoryKey = key
    self:CheckPendingBackSync(key)
    self:ClearContent()

    if isHome then
        if contentPane._headerTitle then
            contentPane._headerTitle:Hide()
        end
        if contentPane._headerSep then
            contentPane._headerSep:Hide()
        end
        if contentPane._collapseAllBtn then
            contentPane._collapseAllBtn:Hide()
        end
        if contentPane._headerSubtitle then
            contentPane._headerSubtitle:Hide()
        end
        if contentPane._copyFromDropdown then
            contentPane._copyFromDropdown:Hide()
        end
        if contentPane._copyFromLabel then
            contentPane._copyFromLabel:Hide()
        end
        if contentPane._defaultsBtn then
            contentPane._defaultsBtn:Hide()
        end
        if contentPane._defaultsInfoIcon then
            contentPane._defaultsInfoIcon:Hide()
        end

        self:StopAsciiAnimation()
        if frame._logo then
            frame._logo:SetText("")
        end
        if frame._logoBtn then
            frame._logoBtn:EnableMouse(false)
        end

        if contentPane._scrollFrame then
            contentPane._scrollFrame:SetPoint("TOPLEFT", contentPane, "TOPLEFT", CONTENT_PADDING, -CONTENT_PADDING)
        end

        if contentPane._placeholder then
            contentPane._placeholder:SetText("")
            contentPane._placeholder:Hide()
        end

        if contentPane._homeContent then
            contentPane._homeContent:Show()
        end

        if scrollContent then
            scrollContent:SetHeight(1)
        end
    else
        if contentPane._homeContent then
            contentPane._homeContent:Hide()
        end

        if wasHome then
            self:AnimateAsciiReveal()
        elseif frame._logo and frame._logo:GetText() == "" then
            frame._logo:SetText(ASCII_LOGO)
        end
        if frame._logoBtn then
            frame._logoBtn:EnableMouse(true)
        end
        if contentPane._headerTitle then
            contentPane._headerTitle:SetText(self:GetCategoryTitle(key))
            contentPane._headerTitle:Show()
        end
        -- Subtitle for custom groups: show "Custom Group X" when a custom name is set
        if contentPane._headerSubtitle then
            local gi = key and key:match("^customGroup(%d)$")
            if gi then
                local CG = addon.CustomGroups
                if CG and CG.GetGroupName and CG.GetGroupName(tonumber(gi)) then
                    -- The Aura List page restyles this shared FontString;
                    -- restore the stock look before reusing it.
                    self:ResetHeaderSubtitle()
                    local sub = contentPane._headerSubtitle
                    sub:SetText("(Custom Group " .. gi .. ")")
                    sub:Show()
                else
                    contentPane._headerSubtitle:Hide()
                end
            else
                contentPane._headerSubtitle:Hide()
            end
        end
        if contentPane._headerSep then
            contentPane._headerSep:Show()
        end

        if contentPane._scrollFrame and contentPane._header then
            contentPane._scrollFrame:SetPoint("TOPLEFT", contentPane._header, "BOTTOMLEFT", CONTENT_PADDING, -CONTENT_PADDING)
        end

        -- Ensure scrollContent width is up to date (handles first-render timing)
        if scrollContent and contentPane._scrollFrame then
            local w = contentPane._scrollFrame:GetWidth()
            if w and w > 0 then
                scrollContent:SetWidth(w - 16)
            end
        end

        local renderer = self._renderers and self._renderers[key]
        if renderer and scrollContent then
            if contentPane._placeholder then
                contentPane._placeholder:Hide()
            end
            renderer(self, scrollContent)
        else
            if contentPane._placeholder then
                contentPane._placeholder:Show()
                contentPane._placeholder:SetText(string.format([[
> Selected: %s

Content renderer not yet implemented.

Navigation key: "%s"
]], self:GetCategoryTitle(key), key or "nil"))
            end
            if scrollContent then
                scrollContent:SetHeight(100)
            end
        end
    end

    -- Update header button active states (Features / Search)
    if frame._SetHeaderButtonActive then
        frame._SetHeaderButtonActive(key)
    end

    if contentPane._scrollFrame then
        contentPane._scrollFrame:SetVerticalScroll(0)
    end

    if contentPane._scrollbar and contentPane._scrollbar.Update then
        C_Timer.After(0.05, function()
            contentPane._scrollbar:Update()
        end)
    end

    self:UpdateCollapseAllButton()
    self:UpdateCopyFromDropdown()
    self:UpdateDefaultsButton()
end

-- Get Category Display Title (auto-derived from NavModel)

-- Sections whose children get a "Prefix: " in the title.
-- Value is the display prefix (allows abbreviation vs NavModel label).
local TITLE_PREFIX = {
    cdm         = "CDM",
    classAuras  = "Class Auras",
    scootAuras  = "ScootAuras",
    unitFrames  = "Unit Frames",
    prd         = "Personal Resource",
    applyAll    = "Apply All",
    sct         = "SCT",
}

local TITLE_OVERRIDES = {
    ufToT         = "Unit Frames: ToT",
    ufFocusTarget = "Unit Frames: ToF",
}

local _titleCache

local function buildTitleCache()
    if _titleCache then return _titleCache end
    _titleCache = { home = "Home", startHere = "Features", search = "Search" }
    for _, section in ipairs(Navigation.NavModel) do
        local prefix = TITLE_PREFIX[section.key]
        if section.children then
            for _, child in ipairs(section.children) do
                if TITLE_OVERRIDES[child.key] then
                    _titleCache[child.key] = TITLE_OVERRIDES[child.key]
                elseif prefix then
                    _titleCache[child.key] = prefix .. ": " .. child.label
                else
                    _titleCache[child.key] = child.label
                end
            end
        end
    end
    return _titleCache
end

function UIPanel:GetCategoryTitle(key)
    if not key then return "Home" end
    -- For custom groups, always use dynamic display name (bypasses cache)
    local gi = key and key:match("^customGroup(%d)$")
    if gi then
        local CG = addon.CustomGroups
        if CG and CG.GetGroupDisplayName then
            local prefix = TITLE_PREFIX["cdm"] or "CDM"
            return prefix .. ": " .. CG.GetGroupDisplayName(tonumber(gi))
        end
    end
    return buildTitleCache()[key] or key
end

function UIPanel:InvalidateTitleCache()
    _titleCache = nil
end

-- Invalidate title cache and refresh header when custom group names change
do
    local CG = addon.CustomGroups
    if CG and CG.RegisterCallback then
        CG.RegisterCallback(function()
            UIPanel:InvalidateTitleCache()
            -- If currently viewing a custom group, refresh the header title and subtitle
            local key = UIPanel._currentCategoryKey
            if key and key:match("^customGroup%d$") then
                local frame = UIPanel.frame
                if frame and frame._contentPane then
                    local contentPane = frame._contentPane
                    if contentPane._headerTitle and contentPane._headerTitle:IsShown() then
                        contentPane._headerTitle:SetText(UIPanel:GetCategoryTitle(key))
                    end
                    if contentPane._headerSubtitle then
                        local gi = tonumber(key:match("^customGroup(%d)$"))
                        if gi and CG.GetGroupName and CG.GetGroupName(gi) then
                            contentPane._headerSubtitle:SetText("(Custom Group " .. gi .. ")")
                            contentPane._headerSubtitle:Show()
                        else
                            contentPane._headerSubtitle:Hide()
                        end
                    end
                end
            end
        end)
    end
end
