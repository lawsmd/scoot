--------------------------------------------------------------------------------
-- personal_resource_display/editmode.lua
-- Two-way mirror between Scoot's PRD components and Blizzard's Edit Mode settings
-- for the Personal Resource Display (Enum.EditModePersonalResourceDisplaySetting).
--
-- Model (same as the CDM/Action Bar "editmode" settings):
--   * Scoot -> Edit Mode happens only on user action: a settings-panel control, a
--     rules-engine action, the Defaults button, or the one-time per-profile push that
--     follows a migration / preset import. Applicators never write native settings.
--   * Edit Mode -> Scoot happens on every Edit Mode commit (SaveLayouts / Edit Mode
--     exit / login), through the existing addon:SyncAllEditModeSettings() loop, which
--     calls component:SyncEditModeSettings() on every registered component.
--
-- All five PRD components share one system frame (PersonalResourceDisplayFrame) and
-- keep frameName = nil, so the generic frameName-driven sync never sees them; this
-- module attaches the two methods the generic layer dispatches to instead.
--
-- Values in AceDB are always UI-facing (px, percent, 0/1 booleans, enum strings).
-- LibEditModeOverride converts to/from Blizzard's stored index / diff-from-min raw
-- values thanks to the PRD flags registered in core/editmode/core.lua.
--
-- Show Bar Text is NOT mirrored here: it is derived (on whenever any PRD text is
-- configured) and owned by text.lua; this module only re-asserts it when the user
-- turned it off inside Edit Mode.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PRD

local PRD_FRAME_NAME = "PersonalResourceDisplayFrame"
local BACKSYNC_SKIP_PASSES = 2

--------------------------------------------------------------------------------
-- Mirror table
--------------------------------------------------------------------------------

local function boolToNative(v) return v and 1 or 0 end
local function nativeToBool(n) return (tonumber(n) or 0) == 1 end

local function snapSlider(m, v)
    v = tonumber(v)
    if v == nil then return nil end
    local step = m.step or 1
    v = m.min + math.floor(((v - m.min) / step) + 0.5) * step
    if v < m.min then v = m.min elseif v > m.max then v = m.max end
    return v
end

-- comp    : Scoot component id
-- key     : AceDB key on that component
-- logical : logical key understood by ResolveSettingId's PRD branch
-- kind    : "bool" | "slider" | "enum" | "custom"
PRD.MIRRORS = {
    { comp = "prdHealth",        key = "hideBar", logical = "hide_health",     kind = "bool", default = false },
    { comp = "prdPower",         key = "hideBar", logical = "hide_power",      kind = "bool", default = false },
    { comp = "prdAltPower",      key = "hideBar", logical = "hide_alt_power",  kind = "bool", default = false },
    { comp = "prdClassResource", key = "hideBar", logical = "hide_class_info", kind = "bool", default = false },
    { comp = "prdClassResource", key = "hideClassInfoOnPlayerFrame", logical = "hide_class_info_on_player_frame", kind = "bool", default = false },

    { comp = "prdHealth", key = "barHeight", logical = "health_bar_height", kind = "slider", min = 10, max = 30, step = 1, default = 15 },
    { comp = "prdPower",  key = "barHeight", logical = "power_bar_height",  kind = "slider", min = 10, max = 30, step = 1, default = 15 },

    { comp = "prdGlobal", key = "scale",      logical = "size",       kind = "slider", min = 70, max = 150, step = 10, default = 100 },
    { comp = "prdGlobal", key = "barWidth",   logical = "bar_width",  kind = "slider", min = 50, max = 150, step = 10, default = 100 },
    { comp = "prdGlobal", key = "barPadding", logical = "padding",    kind = "slider", min = 0,  max = 10,  step = 1,  default = 0 },
    { comp = "prdGlobal", key = "opacity",    logical = "opacity",    kind = "slider", min = 50, max = 100, step = 1,  default = 100 },
    { comp = "prdGlobal", key = "visibleSetting", logical = "visibility", kind = "enum",
        map = { always = 0, combat = 1, never = 2 }, default = "always" },

    -- Native ShowClassColor recolours the health fill with the class colour. Scoot's
    -- Foreground Color mode "class" is the same intent, so the two are one control.
    { comp = "prdHealth", key = "styleForegroundColorMode", logical = "show_class_color", kind = "custom", default = "default",
        toNative = function(v) return (v == "class") and 1 or 0 end,
        fromNative = function(n, current)
            if (tonumber(n) or 0) == 1 then return "class" end
            if current == "class" then return "default" end
            return current
        end },
}

local function toNative(m, value)
    if m.kind == "bool" then
        return boolToNative(value)
    elseif m.kind == "slider" then
        local v = snapSlider(m, value)
        if v == nil then v = m.default end
        return v
    elseif m.kind == "enum" then
        local n = m.map[value]
        if n == nil then n = m.map[m.default] end
        return n
    elseif m.kind == "custom" then
        return m.toNative(value)
    end
end

local function fromNative(m, native, current)
    if m.kind == "bool" then
        return nativeToBool(native)
    elseif m.kind == "slider" then
        return snapSlider(m, native)
    elseif m.kind == "enum" then
        local n = tonumber(native)
        for k, v in pairs(m.map) do
            if v == n then return k end
        end
        return nil
    elseif m.kind == "custom" then
        return m.fromNative(native, current)
    end
end

local function mirrorsFor(compId)
    local out = {}
    for _, m in ipairs(PRD.MIRRORS) do
        if m.comp == compId then out[#out + 1] = m end
    end
    return out
end

local function findMirror(compId, key)
    for _, m in ipairs(PRD.MIRRORS) do
        if m.comp == compId and m.key == key then return m end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Guards
--------------------------------------------------------------------------------

local function getPRDFrame()
    local prd = _G[PRD_FRAME_NAME]
    if not prd or not prd.system then return nil end
    if prd.IsForbidden and prd:IsForbidden() then return nil end
    return prd
end

local function getLEO()
    return LibStub and LibStub("LibEditModeOverride-1.0", true)
end

-- Edit Mode is ready, layouts are loaded, and the PRD system entry exists.
local function editModeReadyForPRD()
    local prd = getPRDFrame()
    if not prd then return false, nil end
    local EM = addon.EditMode
    if not EM or not EM.HasEditModeSettings then return false, nil end
    if not EM.HasEditModeSettings(prd) then return false, nil end
    return true, prd
end

-- Blizzard's Modern/Classic preset layouts cannot be written.
local function activeLayoutIsEditable()
    local LEO = getLEO()
    if not LEO or not LEO.CanEditActiveLayout then return false end
    local ok, editable = pcall(LEO.CanEditActiveLayout, LEO)
    return ok and editable == true
end

-- The AceDB profile and the Edit Mode layout are coupled 1:1 by name. Between a
-- profile change and the deferred SetActiveLayout the two can disagree for a moment;
-- reading or pushing then would cross-contaminate two profiles.
local function profileMatchesLayout()
    local LEO = getLEO()
    if not LEO or not LEO.GetActiveLayout then return false end
    local ok, layoutName = pcall(LEO.GetActiveLayout, LEO)
    if not ok or type(layoutName) ~= "string" then return false end
    local prof = addon.Profiles and addon.Profiles.GetActiveProfile and addon.Profiles:GetActiveProfile()
    return prof == layoutName
end

local function resolveSettingId(prd, logical)
    local resolver = addon.EditMode and addon.EditMode._ResolveSettingId
    if not resolver then return nil end
    return resolver(prd, logical)
end

local componentIsUnconfigured = addon.IsComponentUnconfigured

local function markBackSyncSkip(component, key)
    component._skipNextBackSync = component._skipNextBackSync or {}
    local current = component._skipNextBackSync[key]
    if type(current) == "number" then
        component._skipNextBackSync[key] = math.max(current, BACKSYNC_SKIP_PASSES)
    else
        component._skipNextBackSync[key] = BACKSYNC_SKIP_PASSES
    end
end

-- Returns true when this pass should be skipped for the key (and consumes one pass).
local function consumeBackSyncSkip(component, key)
    local skips = component._skipNextBackSync
    if not skips or not skips[key] then return false end
    local remaining = skips[key]
    if type(remaining) == "number" and remaining > 1 then
        skips[key] = remaining - 1
    else
        skips[key] = nil
    end
    return true
end

--------------------------------------------------------------------------------
-- Scoot -> Edit Mode
--------------------------------------------------------------------------------

-- Push one mirrored setting. Called on user action only. Returns true if a write was
-- issued or unnecessary.
function PRD.PushMirror(compId, key)
    local m = findMirror(compId, key)
    if not m then return false end
    local component = addon.Components and addon.Components[compId]
    if not component or not component.db then return false end
    local ready = editModeReadyForPRD()
    if not ready then return false end
    if not activeLayoutIsEditable() then return false end
    local EM = addon.EditMode
    if not EM.WritePRDSetting then return false end

    local native = toNative(m, component.db[key])
    if native == nil then return false end
    markBackSyncSkip(component, key)
    return EM.WritePRDSetting(m.logical, native)
end

-- Push every explicit (raw-stored) mirrored value of a component, in one save.
-- Values still on their defaults are left to whatever the layout says: "explicit DB
-- wins, defaults yield to native". Returns the number of writes issued.
function PRD.PushAllMirrors(component)
    if not component or not component.db then return 0 end
    if componentIsUnconfigured(component) then return 0 end
    if InCombatLockdown and InCombatLockdown() then return 0 end
    local ready, prd = editModeReadyForPRD()
    if not ready or not activeLayoutIsEditable() then return 0 end
    local EM = addon.EditMode
    if not EM.WritePRDSetting or not EM.GetSetting then return 0 end

    local wrote = 0
    for _, m in ipairs(mirrorsFor(component.id)) do
        if rawget(component.db, m.key) ~= nil then
            local native = toNative(m, component.db[m.key])
            local id = resolveSettingId(prd, m.logical)
            if native ~= nil and id ~= nil then
                local current = EM.GetSetting(prd, id)
                if current == nil or tonumber(current) ~= tonumber(native) then
                    markBackSyncSkip(component, m.key)
                    EM.WritePRDSetting(m.logical, native, { skipSave = true })
                    wrote = wrote + 1
                end
            end
        end
    end
    if wrote > 0 and EM.SaveOnly then
        EM.SaveOnly()
    end
    return wrote
end

-- Restore Blizzard's defaults for a component's mirrored settings (Defaults button).
function PRD.PushDefaults(compId)
    local list = mirrorsFor(compId)
    if #list == 0 then return 0 end
    if InCombatLockdown and InCombatLockdown() then return 0 end
    local ready, prd = editModeReadyForPRD()
    if not ready or not activeLayoutIsEditable() then return 0 end
    local EM = addon.EditMode
    if not EM.WritePRDSetting or not EM.GetSetting then return 0 end

    local wrote = 0
    for _, m in ipairs(list) do
        local native = toNative(m, m.default)
        local id = resolveSettingId(prd, m.logical)
        if native ~= nil and id ~= nil then
            local current = EM.GetSetting(prd, id)
            if current == nil or tonumber(current) ~= tonumber(native) then
                EM.WritePRDSetting(m.logical, native, { skipSave = true })
                wrote = wrote + 1
            end
        end
    end
    if wrote > 0 and EM.SaveOnly then
        EM.SaveOnly()
    end
    return wrote
end

--------------------------------------------------------------------------------
-- Pending per-profile push (migration V7, preset import, profile import)
--------------------------------------------------------------------------------

-- Mark a profile table so its explicit PRD mirror values get pushed to Edit Mode
-- the first time it is active with Edit Mode ready.
function PRD.MarkProfilePendingNativePush(profileTable)
    if type(profileTable) ~= "table" then return end
    profileTable.prdSettings = profileTable.prdSettings or {}
    profileTable.prdSettings.pendingNativePush = true
end

local function activeProfileHasPendingPush()
    local profile = addon.db and addon.db.profile
    local s = profile and rawget(profile, "prdSettings")
    return s and s.pendingNativePush == true
end

local function clearPendingPush()
    local profile = addon.db and addon.db.profile
    local s = profile and rawget(profile, "prdSettings")
    if s then s.pendingNativePush = nil end
end

local PRD_COMPONENT_IDS = { "prdGlobal", "prdHealth", "prdPower", "prdAltPower", "prdClassResource" }

-- Consume the marker when every guard holds. Called at the top of each component's
-- read pass so the push always precedes the first read.
function PRD._ConsumePendingNativePush()
    if not activeProfileHasPendingPush() then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local ready, prd = editModeReadyForPRD()
    if not ready then return false end
    if not activeLayoutIsEditable() then
        -- Nothing can ever be pushed into a Blizzard preset layout; drop the marker.
        clearPendingPush()
        return false
    end
    if not profileMatchesLayout() then return false end
    -- A layout inserted verbatim from an old preset payload carries only PRD settings
    -- 0/1 until Blizzard reconciles it; wait for a fully populated system entry.
    local hidePowerId = resolveSettingId(prd, "hide_power")
    if hidePowerId == nil or addon.EditMode.GetSetting(prd, hidePowerId) == nil then
        return false
    end

    for _, id in ipairs(PRD_COMPONENT_IDS) do
        local component = addon.Components and addon.Components[id]
        if component then
            PRD.PushAllMirrors(component)
        end
    end
    clearPendingPush()
    return true
end

--------------------------------------------------------------------------------
-- Edit Mode -> Scoot (read-back)
--------------------------------------------------------------------------------

local function notifyPanel(componentId, key)
    local panel = addon.UI and addon.UI.SettingsPanel
    if panel and type(panel.HandleEditModeBackSync) == "function" then
        panel:HandleEditModeBackSync(componentId, key)
    end
end

-- Attached to every PRD component as :SyncEditModeSettings(). Returns true if AceDB changed.
local function syncEditModeSettings(component)
    PRD._ConsumePendingNativePush()

    -- Zero-Touch: never back-sync into an unconfigured component (same rule as the
    -- generic Component:SyncEditModeSettings).
    if componentIsUnconfigured(component) then return false end
    if addon.EditMode and addon.EditMode._syncingEM then return false end
    local ready, prd = editModeReadyForPRD()
    if not ready then return false end
    if not profileMatchesLayout() then return false end
    local EM = addon.EditMode
    if not EM.GetSetting then return false end

    local pending = EM._pendingWrites
    local changed = false
    for _, m in ipairs(mirrorsFor(component.id)) do
        local id = resolveSettingId(prd, m.logical)
        if id ~= nil and not consumeBackSyncSkip(component, m.key) then
            -- A combat-queued write for this setting has not reached the layout yet;
            -- reading now would clobber the user's value with the stale native one.
            local queued = pending and pending[PRD_FRAME_NAME .. ":" .. tostring(id)]
            if not queued then
                local native = EM.GetSetting(prd, id)
                if native ~= nil then
                    local current = component.db[m.key]
                    local value = fromNative(m, native, current)
                    if value ~= nil and current ~= value then
                        component.db[m.key] = value
                        changed = true
                        notifyPanel(component.id, m.key)
                    end
                end
            end
        end
    end

    -- Show Bar Text is Scoot-driven while any PRD text is configured. If it reads 0
    -- here, the user turned it off inside Edit Mode: forget the latch so the next
    -- apply turns it back on (the styled overlay depends on the native stream).
    if component.id == "prdHealth" and PRD._anyPRDTextConfigured and PRD._anyPRDTextConfigured() then
        local textId = resolveSettingId(prd, "show_bar_text")
        if textId ~= nil then
            local native = EM.GetSetting(prd, textId)
            if native ~= nil and tonumber(native) == 0 and PRD._resetNativeBarTextLatch then
                PRD._resetNativeBarTextLatch()
            end
        end
    end

    return changed
end

-- Attached as :SyncSettingToEditMode(settingId, opts); the generic
-- SyncComponentSettingToEditMode dispatches here for these components.
local function syncSettingToEditMode(component, settingId, opts)
    return PRD.PushMirror(component.id, settingId)
end

--------------------------------------------------------------------------------
-- Method attachment (components are created by core.lua's initializer)
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    for _, id in ipairs(PRD_COMPONENT_IDS) do
        local component = self.Components and self.Components[id]
        if component then
            component.SyncEditModeSettings = syncEditModeSettings
            component.SyncSettingToEditMode = syncSettingToEditMode
        end
    end
end, "prd")
