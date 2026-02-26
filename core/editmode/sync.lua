local _, addon = ...
local LEO = LibStub("LibEditModeOverride-1.0")

-- Aliases for internals promoted by core.lua
local ResolveSettingId = addon.EditMode._ResolveSettingId
local getEditModeState = addon.EditMode._getEditModeState
local roundPositionValue = addon.EditMode._roundPositionValue
local _ForceObjectiveTrackerRelayout = addon.EditMode._ForceObjectiveTrackerRelayout
local _GetUnitFrameForUnit = addon.EditMode._GetUnitFrameForUnit

local function _lower(s)
    if type(s) ~= "string" then return "" end
    return string.lower(s)
end

--[[----------------------------------------------------------------------------
    Full Sync Functions (Addon DB -> Edit Mode)
----------------------------------------------------------------------------]]--

function addon.EditMode.SyncComponentSettingToEditMode(component, settingId, opts)
    opts = opts or {}
    local frame = _G[component.frameName]
    if not frame or not addon.EditMode.HasEditModeSettings(frame) then return false end

    local function markBackSyncSkip(forSetting, count)
        if not component then return end
        component._skipNextBackSync = component._skipNextBackSync or {}
        local key = forSetting or settingId
        local current = component._skipNextBackSync[key]
        local desired = tonumber(count) or 2
        if type(current) == "number" then
            component._skipNextBackSync[key] = math.max(current, desired)
        else
            component._skipNextBackSync[key] = desired
        end
    end

    local setting = component.settings[settingId]
    if not setting or setting.type ~= "editmode" then return false end

    local dbValue = component.db[settingId]
    if dbValue == nil then
        dbValue = setting.default
    end
    if dbValue == nil then return false end

    -- (removed global-propagation of Orientation; each bar updates independently)

    local editModeValue
    -- Convert addon DB value to the value Edit Mode expects
    if settingId == "orientation" then
        -- Resolve orientation setting id dynamically for non-CooldownViewer systems
        setting.settingId = setting.settingId or ResolveSettingId(frame, "orientation") or setting.settingId
        editModeValue = (dbValue == "H") and 0 or 1
    elseif settingId == "columns" then
        editModeValue = tonumber(dbValue) or 12
    elseif settingId == "height" then
        -- Objective Tracker: Height slider
        setting.settingId = setting.settingId or ResolveSettingId(frame, "height") or setting.settingId
        editModeValue = tonumber(dbValue)
    elseif settingId == "textSize" then
        -- Objective Tracker: Text Size slider
        setting.settingId = setting.settingId or ResolveSettingId(frame, "text_size") or setting.settingId
        editModeValue = tonumber(dbValue)
    elseif component and component.id == "microBar" and settingId == "direction" then
        -- Micro Bar: 'Order' uses 0 = default (Right/Up), 1 = reverse (Left/Down)
        local orientation = component.db.orientation or "H"
        if orientation == "H" then
            editModeValue = (dbValue == "left") and 1 or 0 -- default Right => 0
        else
            editModeValue = (dbValue == "down") and 1 or 0 -- default Up => 0
        end
        setting.settingId = setting.settingId or 1
    elseif settingId == "iconWrap" then
        -- Icon Wrap is stored as a simple 0/1 index whose semantics depend on orientation:
        --  Horizontal: 0=Down, 1=Up
        --  Vertical:   0=Left, 1=Right
        setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_wrap") or setting.settingId
        local o = component.db.orientation or "H"
        local v = tostring(dbValue)
        if o == "H" then
            editModeValue = (v == "up") and 1 or 0
        else
            editModeValue = (v == "right") and 1 or 0
        end
    elseif settingId == "direction" then
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        if sysEnum and frame.system == sysEnum.AuraFrame then
            -- Aura Frame: direction is also a 0/1 index whose meaning depends on orientation:
            --  Horizontal: 0=Left,  1=Right
            --  Vertical:   0=Up,    1=Down
            setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_direction") or setting.settingId
            local o = component.db.orientation or "H"
            local v = tostring(dbValue)
            if o == "H" then
                editModeValue = (v == "right") and 1 or 0
            else
                editModeValue = (v == "up") and 1 or 0
            end
        else
            -- Default mapping used by Cooldown Viewer / Action Bars (orientation-aware)
            local orientation = component.db.orientation or "H"
            if orientation == "H" then
                editModeValue = (dbValue == "right") and 1 or 0
            else
                editModeValue = (dbValue == "up") and 1 or 0
            end
        end
    elseif settingId == "iconPadding" then
        -- WRITING to the library requires the RAW value. Ranges:
        --  - Cooldown Viewer / Action Bars / Tracked Bars: 2–14
        --  - Aura Frame (Buffs/Debuffs): 5–15
        local pad = tonumber(dbValue)
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        if sysEnum and frame and frame.system == sysEnum.AuraFrame then
            if not pad then pad = 10 end
            if pad < 5 then pad = 5 elseif pad > 15 then pad = 15 end
        else
            if not pad then pad = 2 end
            if pad < 2 then pad = 2 elseif pad > 14 then pad = 14 end
        end
        editModeValue = pad
    elseif settingId == "iconLimit" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_limit") or setting.settingId
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        local minV, maxV, defaultV = 1, 32, 8
        if sysEnum and frame and frame.system == sysEnum.AuraFrame then
            local isBuffFrame = frame == _G.BuffFrame
            minV = isBuffFrame and 2 or 1
            maxV = isBuffFrame and 32 or 16
            defaultV = isBuffFrame and 11 or math.min(math.max(defaultV, minV), maxV)
        end
        local limit = tonumber(dbValue)
        if not limit then limit = defaultV end
        limit = math.floor(limit + 0.5)
        if limit < minV then limit = minV elseif limit > maxV then limit = maxV end
        editModeValue = limit
    elseif settingId == "iconSize" then
        -- Resolve id for non-CDM systems and send raw percent (50–200), snapped to 10.
        -- LibEditModeOverride handles index-vs-raw conversion for systems where Icon Size
        -- behaves like an index slider (e.g., Cooldown Viewer, Aura Frame).
        setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_size") or setting.settingId
        local desiredRaw = tonumber(dbValue) or 100
        if desiredRaw < 50 then desiredRaw = 50 end
        if desiredRaw > 200 then desiredRaw = 200 end
        desiredRaw = math.floor(desiredRaw / 10 + 0.5) * 10
        editModeValue = desiredRaw
    elseif settingId == "barWidth" then
        -- Tracked Bars Bar Width Scale: 50-200%, step 1, index-based
        setting.settingId = setting.settingId or ResolveSettingId(frame, "bar_width_scale") or setting.settingId
        local desiredRaw = tonumber(dbValue) or 100
        if desiredRaw < 50 then desiredRaw = 50 end
        if desiredRaw > 200 then desiredRaw = 200 end
        desiredRaw = math.floor(desiredRaw + 0.5)
        editModeValue = desiredRaw
    elseif settingId == "size" or settingId == "mapSize" then
        -- Minimap Size: 50-200%, step 10, index-based
        setting.settingId = setting.settingId or ResolveSettingId(frame, "size") or setting.settingId
        local desiredRaw = tonumber(dbValue) or 100
        if desiredRaw < 50 then desiredRaw = 50 end
        if desiredRaw > 200 then desiredRaw = 200 end
        desiredRaw = math.floor(desiredRaw / 10 + 0.5) * 10
        editModeValue = desiredRaw
    elseif settingId == "opacity" then
        -- Write RAW percent. Cooldown Viewer uses 50..100; Objective Tracker uses 0..100.
        local v = tonumber(dbValue) or 100
        if frame and frame.system == 12 then
            if v < 0 then v = 0 elseif v > 100 then v = 100 end
        else
            if v < 50 then v = 50 elseif v > 100 then v = 100 end
        end
        local resolved = ResolveSettingId(frame, "opacity")
        if resolved then setting.settingId = resolved end
        editModeValue = v
    elseif component and component.id == "microBar" and (settingId == "menuSize" or settingId == "eyeSize") then
        -- Micro Bar sliders: library expects RAW values (min..max, step 5)
        local minV = (settingId == "menuSize") and 70 or 50
        local maxV = (settingId == "menuSize") and 200 or 150
        local step = 5
        local raw = tonumber(dbValue) or ((minV + maxV) / 2)
        if raw < minV then raw = minV elseif raw > maxV then raw = maxV end
        raw = minV + math.floor(((raw - minV) / step) + 0.5) * step -- snap to step within range
        setting.settingId = setting.settingId or ((settingId == "menuSize") and 2 or 3)
        markBackSyncSkip()
        addon.EditMode.SetSetting(frame, setting.settingId, raw)
        if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
        return true
    elseif settingId == "displayMode" then
        -- Map addon values to bar content dropdown: both/icon/name
        setting.settingId = setting.settingId or ResolveSettingId(frame, "bar_content") or ResolveSettingId(frame, "display_mode") or setting.settingId
        local v = tostring(dbValue)
        -- Assume EM dropdown values: 0=Both,1=IconOnly,2=NameOnly (feature-detected at runtime when possible)
        if setting.settingId then
            editModeValue = (v == "icon") and 1 or (v == "name" and 2 or 0)
        end
    elseif settingId == "visibilityMode" then
        -- 0 = always, 1 = only in combat, 2 = hidden
        local v = tostring(dbValue)
        editModeValue = (v == "combat") and 1 or (v == "never" and 2 or 0)
        setting.settingId = setting.settingId or ResolveSettingId(frame, "visibility") or setting.settingId
    elseif settingId == "showTimer" then
        -- Checkbox mapping for Edit Mode: true/false -> 1/0. We resolve the dynamic setting id so we don't rely on stale enums.
        setting.settingId = setting.settingId or ResolveSettingId(frame, "show_timer") or setting.settingId
        local v = not not dbValue
        editModeValue = v and 1 or 0
    elseif settingId == "showTooltip" then
        -- Checkbox mapping for Edit Mode: true/false -> 1/0. Same dynamic id resolution as above.
        setting.settingId = setting.settingId or ResolveSettingId(frame, "show_tooltip") or setting.settingId
        local v = not not dbValue
        editModeValue = v and 1 or 0
    elseif settingId == "hideWhenInactive" then
        -- Resolve dynamically; map boolean to 1/0 for Edit Mode API
        setting.settingId = setting.settingId or ResolveSettingId(frame, "hide_when_inactive") or setting.settingId
        local v = not not dbValue
        editModeValue = v and 1 or 0
    -- Damage Meter settings
    elseif component and component.id == "damageMeter" then
        -- DamageMeter-specific handling
        if settingId == "showSpecIcon" or settingId == "showClassColor" then
            -- Checkbox settings: boolean -> 0/1
            setting.settingId = setting.settingId or ResolveSettingId(frame, settingId) or setting.settingId
            editModeValue = (dbValue and true or false) and 1 or 0
        elseif settingId == "style" then
            -- Style dropdown: 0=Default, 1=Bordered, 2=Thin
            setting.settingId = setting.settingId or ResolveSettingId(frame, "style") or setting.settingId
            local v = tonumber(dbValue) or 0
            if v < 0 then v = 0 elseif v > 2 then v = 2 end
            editModeValue = v
        elseif settingId == "frameWidth" then
            -- Frame Width slider: 300-600, step 10
            setting.settingId = setting.settingId or ResolveSettingId(frame, "frame_width") or setting.settingId
            local v = tonumber(dbValue) or 300
            v = math.floor((v - 300) / 10 + 0.5) * 10 + 300
            if v < 300 then v = 300 elseif v > 600 then v = 600 end
            editModeValue = v
        elseif settingId == "frameHeight" then
            -- Frame Height slider: 120-400, step 10
            setting.settingId = setting.settingId or ResolveSettingId(frame, "frame_height") or setting.settingId
            local v = tonumber(dbValue) or 200
            v = math.floor((v - 120) / 10 + 0.5) * 10 + 120
            if v < 120 then v = 120 elseif v > 400 then v = 400 end
            editModeValue = v
        elseif settingId == "barHeight" then
            -- Bar Height slider: 18-40, step 1
            setting.settingId = setting.settingId or ResolveSettingId(frame, "bar_height") or setting.settingId
            local v = tonumber(dbValue) or 20
            v = math.floor(v + 0.5)
            if v < 18 then v = 18 elseif v > 40 then v = 40 end
            editModeValue = v
        elseif settingId == "padding" then
            -- Padding slider: 2-10, step 1
            setting.settingId = setting.settingId or ResolveSettingId(frame, "padding") or setting.settingId
            local v = tonumber(dbValue) or 4
            v = math.floor(v + 0.5)
            if v < 2 then v = 2 elseif v > 10 then v = 10 end
            editModeValue = v
        elseif settingId == "background" then
            -- Background transparency slider: 0-100%, step 5
            setting.settingId = setting.settingId or ResolveSettingId(frame, "background") or setting.settingId
            local v = tonumber(dbValue) or 80
            v = math.floor(v / 5 + 0.5) * 5
            if v < 0 then v = 0 elseif v > 100 then v = 100 end
            editModeValue = v
        elseif settingId == "opacity" then
            -- Opacity slider: 50-100, step 5
            setting.settingId = setting.settingId or ResolveSettingId(frame, "opacity") or setting.settingId
            local v = tonumber(dbValue) or 100
            v = math.floor((v - 50) / 5 + 0.5) * 5 + 50
            if v < 50 then v = 50 elseif v > 100 then v = 100 end
            editModeValue = v
        elseif settingId == "textSize" then
            -- Text Size slider: 50-150, step 10
            setting.settingId = setting.settingId or ResolveSettingId(frame, "text_size") or setting.settingId
            local v = tonumber(dbValue) or 100
            v = math.floor((v - 50) / 10 + 0.5) * 10 + 50
            if v < 50 then v = 50 elseif v > 150 then v = 150 end
            editModeValue = v
        elseif settingId == "visibility" then
            -- Visibility dropdown: 0=Always, 1=InCombat, 2=Hidden
            setting.settingId = setting.settingId or ResolveSettingId(frame, "visibility") or setting.settingId
            local v = tonumber(dbValue) or 0
            if v < 0 then v = 0 elseif v > 2 then v = 2 end
            editModeValue = v
        else
            -- Default numeric handling for other DamageMeter settings
            editModeValue = tonumber(dbValue) or 0
        end
    else
        editModeValue = tonumber(dbValue) or 0
    end

    if editModeValue ~= nil then
        local wrote = false
        local function persist()
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
        end

        -- Opacity
        if settingId == "opacity" then
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            wrote = true
            persist()
            return true
        elseif settingId == "height" then
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            wrote = true
            persist()
            return true
        elseif settingId == "textSize" then
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            wrote = true
            persist()
            return true
        elseif settingId == "displayMode" then
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            wrote = true
            persist()
            return true
        elseif settingId == "orientation" then
            setting.settingId = setting.settingId or ResolveSettingId(frame, "orientation") or setting.settingId
            if not setting.settingId then
                if type(component.id) == "string" and component.id:match("^actionBar%d$") then
                    setting.settingId = 0
                end
            end
            local emVal = (component.db.orientation == "H") and 0 or 1
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, emVal)
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            return true
        elseif settingId == "columns" and type(component.id) == "string" and (component.id:match("^actionBar%d$") or component.id == "stanceBar") then
            local value = tonumber(component.db.columns)
            if not value then value = 1 end
            value = math.floor(math.max(1, math.min(4, value)))
            setting.settingId = setting.settingId or ResolveSettingId(frame, "num_rows") or setting.settingId
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, value)
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            return true
        elseif settingId == "numIcons" then
            local value = tonumber(component.db.numIcons)
            if not value then value = 12 end
            value = math.floor(math.max(6, math.min(12, value)))
            setting.settingId = setting.settingId or ResolveSettingId(frame, "num_icons") or setting.settingId
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, value)
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            return true
        elseif settingId == "visibilityMode" then
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            wrote = true
            persist()
            return true
        elseif component and component.id == "microBar" and settingId == "direction" then
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            wrote = true
            persist()
            return true
        elseif settingId == "barVisibility" then
            setting.settingId = setting.settingId or ResolveSettingId(frame, "visibility") or setting.settingId
            local map = { always = 0, combat = 1, not_in_combat = 2, hidden = 3 }
            local idx = map[tostring(dbValue)]
            if idx == nil then idx = 0 end
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, idx)
            wrote = true
            persist()
            return true
        elseif settingId == "hideBarArt" then
            setting.settingId = setting.settingId or ResolveSettingId(frame, "hide_bar_art") or setting.settingId
            local v = not not dbValue
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, v and 1 or 0)
            wrote = true
            persist()
            return true
        elseif settingId == "hideBarScrolling" then
            setting.settingId = setting.settingId or ResolveSettingId(frame, "hide_bar_scrolling") or setting.settingId
            local v = not not dbValue
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, v and 1 or 0)
            wrote = true
            persist()
            return true
        elseif settingId == "alwaysShowButtons" then
            setting.settingId = setting.settingId or ResolveSettingId(frame, "always_show_buttons") or setting.settingId
            local v = not not dbValue
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, v and 1 or 0)
            wrote = true
            persist()
            return true
        elseif settingId == "iconLimit" then
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            wrote = true
            persist()
            return true
        elseif settingId == "iconSize" then
            markBackSyncSkip(nil, 2)
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            if component and (component.id == "buffs" or component.id == "debuffs") then
                component._pendingAuraIconSizeTarget = editModeValue
                if GetTime then
                    component._pendingAuraIconSizeExpiry = GetTime() + 2.0
                else
                    component._pendingAuraIconSizeExpiry = os and os.time and (os.time() + 2) or nil
                end
            end
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            return true
        elseif settingId == "barWidth" then
            markBackSyncSkip(nil, 2)
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            return true
        elseif settingId == "size" or settingId == "mapSize" then
            -- Minimap Size: Write raw percent (50-200)
            markBackSyncSkip(nil, 2)
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            return true
        elseif settingId == "iconPadding" then
            setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_padding") or setting.settingId
            local pad = tonumber(component.db.iconPadding)
            local sysEnum = _G.Enum and _G.Enum.EditModeSystem
            if sysEnum and frame and frame.system == sysEnum.AuraFrame then
                if not pad then pad = 10 end
                if pad < 5 then pad = 5 elseif pad > 15 then pad = 15 end
            else
                if not pad then pad = 2 end
                if pad < 2 then pad = 2 elseif pad > 14 then pad = 14 end
            end
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, pad)
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            return true
        -- Damage Meter write handling
        elseif component and component.id == "damageMeter" then
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            wrote = true
            persist()
            return true
        end
        -- Others: skip write if no change
        local current = addon.EditMode.GetSetting(frame, setting.settingId)
        if current ~= editModeValue then
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            wrote = true
            persist()
            return true
        end
        return false
    end
    return false
end

-- This is the main function for pushing the addon's state to Edit Mode.
function addon.EditMode.SyncComponentToEditMode(component, opts)
    opts = opts or {}
    local frame = _G[component.frameName]
    if not frame or not addon.EditMode.HasEditModeSettings(frame) then return end

    if addon.EditMode._syncingEM then return end
    addon.EditMode._syncingEM = true

    -- Ensure layouts are loaded before we attempt to write
    addon.EditMode.LoadLayouts()

    -- 1. Sync Position
    local x = component.db.positionX or 0
    local y = component.db.positionY or 0
    addon.EditMode.ReanchorFrame(frame, "CENTER", "UIParent", "CENTER", x, y)

    -- 2. Sync all other Edit Mode settings (pass skipApply to avoid taint)
    for settingId, setting in pairs(component.settings) do
        if type(setting) == "table" and setting.type == "editmode" then
            addon.EditMode.SyncComponentSettingToEditMode(component, settingId, { skipApply = true })
        end
    end

    -- 3. Save settings
    if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end

    -- Hold the syncing guard briefly to avoid back-sync races from SaveLayouts callbacks
    local function clearGuard()
        addon.EditMode._syncingEM = false
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.35, clearGuard)
    else
        clearGuard()
    end
end

-- Position-only sync: Use this when ONLY position (X/Y) changed.
-- This avoids the cascade of syncing all Edit Mode settings (orientation, columns, etc.)
-- which would trigger many ResolveSettingId calls and LoadLayouts() invocations.
-- NOTE: This function handles SaveOnly internally - callers should NOT
-- call SaveOnly again after calling this function.
function addon.EditMode.SyncComponentPositionToEditMode(component)
    if not component then return end
    local frame = _G[component.frameName]
    if not frame then return end

    -- Guard against re-entry during sync
    if addon.EditMode._syncingPosition then return end
    addon.EditMode._syncingPosition = true

    -- Only load layouts if not already loaded (avoid cascade)
    if LEO and LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then
        addon.EditMode.LoadLayouts()
    end

    -- Sync Position only
    local x = component.db.positionX or 0
    local y = component.db.positionY or 0
    addon.EditMode.ReanchorFrame(frame, "CENTER", "UIParent", "CENTER", x, y)

    if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end

    -- Clear guard after a brief delay to avoid back-sync races
    local function clearGuard()
        addon.EditMode._syncingPosition = false
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.35, clearGuard)
    else
        clearGuard()
    end
end


--[[----------------------------------------------------------------------------
    Aura Frame Icon Size Late Backfill
----------------------------------------------------------------------------]]--
local function _AuraBackfillDebugEnabled()
    return addon and addon._dbgAuraIconSize
end

local function _AuraBackfillLog(fmt, ...)
    if not _AuraBackfillDebugEnabled() then return end
    addon.EditMode._auraIconSizeLog = addon.EditMode._auraIconSizeLog or {}
    local prefix = ""
    prefix = string.format("[%.3f] ", GetTime())
    local message = fmt and string.format(fmt, ...) or ""
    table.insert(addon.EditMode._auraIconSizeLog, prefix .. message)
end

local _pendingAuraIconSizeBackfill = {}

local function _ClampAuraIconSizePercent(pct)
    if not pct then return nil end
    pct = tonumber(pct)
    if not pct then return nil end
    pct = math.floor(pct + 0.5)
    if pct < 50 then pct = 50 elseif pct > 200 then pct = 200 end
    local step = 10
    local snapped = step * math.floor((pct / step) + 0.5)
    if snapped < 50 then snapped = 50 elseif snapped > 200 then snapped = 200 end
    return snapped
end

local function _ReadAuraFrameIconPercent(frame)
    if not frame or not frame.AuraContainer then return nil end
    local scale = tonumber(frame.AuraContainer.iconScale)
    if not scale then return nil end
    return _ClampAuraIconSizePercent(scale * 100)
end

function addon.EditMode.QueueAuraIconSizeBackfill(componentId, opts)
    if componentId ~= "buffs" and componentId ~= "debuffs" then return end
    if not C_Timer or not C_Timer.After then return end
    if _pendingAuraIconSizeBackfill[componentId] then return end
    local origin = opts and opts.origin
    local attempt = (opts and opts.attempt) or 0
    local retryDelays = opts and opts.retryDelays
    if type(retryDelays) ~= "table" then
        retryDelays = nil
    end

    local delay = opts and tonumber(opts.delay) or 1.2
    if delay < 0 then delay = 0 end

    _pendingAuraIconSizeBackfill[componentId] = true

    if _AuraBackfillDebugEnabled() and attempt == 0 then
        addon.EditMode._auraIconSizeLog = {}
    end
    _AuraBackfillLog("QueueAuraIconSizeBackfill start component=%s origin=%s attempt=%d delay=%.2fs", tostring(componentId), tostring(origin), attempt, delay)

    local titlePrefix = (componentId == "buffs") and "Buffs" or (componentId == "debuffs" and "Debuffs" or tostring(componentId or "Aura"))

    C_Timer.After(delay, function()
        _pendingAuraIconSizeBackfill[componentId] = nil
        if not addon or not addon.Components then return end
        _AuraBackfillLog("Timer fired component=%s origin=%s attempt=%d", tostring(componentId), tostring(origin), attempt)

        local updated = false

        local function scheduleRetry(nextAttempt, reason, overrideDelay)
            if not nextAttempt then return false end
            local nextDelay = overrideDelay
            if not nextDelay and retryDelays and retryDelays[nextAttempt] then
                nextDelay = retryDelays[nextAttempt]
            end
            if not nextDelay then return false end
            if nextDelay < 0 then nextDelay = 0 end
            _AuraBackfillLog("Scheduling retry attempt=%d in %.2fs (reason=%s)", nextAttempt, nextDelay, tostring(reason or "retry"))
            addon.EditMode.QueueAuraIconSizeBackfill(componentId, {
                delay = nextDelay,
                origin = reason or origin or "retry",
                attempt = nextAttempt,
                retryDelays = retryDelays,
            })
            return true
        end

        local function refreshPanelIfVisible()
            -- v2 panel handles its own refresh via HandleEditModeBackSync; nothing needed here
        end

        if addon.EditMode and addon.EditMode._syncingEM then
            _AuraBackfillLog("Still syncing with Edit Mode; scheduling retry")
            local nextAttempt = attempt + 1
            local guardOrigin = (origin and (tostring(origin) .. ":guard")) or "retry_guard"
            if not scheduleRetry(nextAttempt, guardOrigin) then
                scheduleRetry(nextAttempt, guardOrigin, 0.2)
            end
            return
        end

        local component = addon.Components[componentId]
        if not component or not component.db then return end

        if addon.EditMode and addon.EditMode.SyncEditModeSettingToComponent then
            local before = component.db.iconSize
            local changed = addon.EditMode.SyncEditModeSettingToComponent(component, "iconSize")
            _AuraBackfillLog("SyncEditModeSettingToComponent returned changed=%s (db before=%s after=%s)", tostring(changed), tostring(before), tostring(component.db.iconSize))
            if changed then
                refreshPanelIfVisible()
                if _AuraBackfillDebugEnabled() and addon.DebugShowWindow then
                    addon.DebugShowWindow(string.format("%s Icon Size Backfill (%s)", titlePrefix, tostring(origin or "Sync")), addon.EditMode._auraIconSizeLog)
                end
                return
            end
        end

        local frame = _G[component.frameName]
        if not frame then return end

        local percent = _ReadAuraFrameIconPercent(frame)
        _AuraBackfillLog("AuraContainer iconScale-derived percent=%s", tostring(percent))
        if not percent then return end

        if component._pendingAuraIconSizeTarget then
            local expire = component._pendingAuraIconSizeExpiry
            local now = GetTime and GetTime() or nil
            if expire and now and now >= expire then
                component._pendingAuraIconSizeTarget = nil
                component._pendingAuraIconSizeExpiry = nil
                _AuraBackfillLog("Pending target expired; clearing guard")
            else
                local target = component._pendingAuraIconSizeTarget
                if target and math.abs(percent - target) >= 0.5 then
                    _AuraBackfillLog("Pending target %s differs from fallback percent=%s; retrying instead of reverting", tostring(target), tostring(percent))
                    local nextAttempt = attempt + 1
                    if scheduleRetry(nextAttempt, "pending_target") then return end
                    return
                end
            end
        end

        if component.db.iconSize ~= percent then
            _AuraBackfillLog("Updating component.db.iconSize from %s to %s via fallback", tostring(component.db.iconSize), tostring(percent))
            component.db.iconSize = percent
            updated = true
            if component._pendingAuraIconSizeTarget and math.abs((tonumber(component._pendingAuraIconSizeTarget) or 0) - percent) < 0.5 then
                component._pendingAuraIconSizeTarget = nil
                component._pendingAuraIconSizeExpiry = nil
            end
            refreshPanelIfVisible()
        else
            _AuraBackfillLog("No change to component.db.iconSize (already %s)", tostring(percent))
            refreshPanelIfVisible()
        end

        if _AuraBackfillDebugEnabled() and addon.DebugShowWindow then
            addon.DebugShowWindow(string.format("%s Icon Size Backfill (%s)", titlePrefix, tostring(origin or "Fallback")), addon.EditMode._auraIconSizeLog)
        end

        if not updated then
            local nextAttempt = attempt + 1
            if scheduleRetry(nextAttempt, (origin and (tostring(origin) .. ":poll")) or "retry_poll") then
                return
            end
        end
    end)
end


--[[----------------------------------------------------------------------------
    Back-Sync Functions (Edit Mode -> Addon DB)
----------------------------------------------------------------------------]]--

-- Syncs a single simple setting from Edit Mode to the addon DB
function addon.EditMode.SyncEditModeSettingToComponent(component, settingId)
    local frame = _G[component.frameName]
    if not frame or not addon.EditMode.HasEditModeSettings(frame) then return false end

    if addon.EditMode._syncingEM then return false end

    local setting = component.settings[settingId]
    if not setting or setting.type ~= "editmode" then return false end

    if component._skipNextBackSync and component._skipNextBackSync[settingId] then
        local remaining = component._skipNextBackSync[settingId]
        if type(remaining) == "number" then
            if remaining <= 1 then
                component._skipNextBackSync[settingId] = nil
            else
                component._skipNextBackSync[settingId] = remaining - 1
            end
        else
            component._skipNextBackSync[settingId] = nil
        end
        return false
    end

    -- Resolve dynamic ids if needed
    if settingId == "visibilityMode" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "visibility") or setting.settingId
    elseif settingId == "showTimer" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "show_timer") or setting.settingId
    elseif settingId == "showTooltip" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "show_tooltip") or setting.settingId
    elseif settingId == "hideWhenInactive" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "hide_when_inactive") or setting.settingId
    elseif settingId == "height" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "height") or setting.settingId
    elseif settingId == "textSize" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "text_size") or setting.settingId
    elseif settingId == "opacity" then
        -- Prefer dynamic resolver (system-specific); only fall back to the stable Cooldown Viewer enum/index.
        setting.settingId = setting.settingId or ResolveSettingId(frame, "opacity") or setting.settingId
        if not setting.settingId then
            local EM = _G.Enum and _G.Enum.EditModeCooldownViewerSetting
            if EM and EM.Opacity then setting.settingId = EM.Opacity else setting.settingId = 5 end
        end
    elseif settingId == "iconWrap" then
        -- Aura Frame and any other systems that expose an "Icon Wrap" dropdown
        setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_wrap") or setting.settingId
    elseif settingId == "direction" then
        -- Aura Frame "Icon Direction" and other systems sharing the logical key
        setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_direction") or setting.settingId
    end

    if settingId == "orientation" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "orientation") or setting.settingId
    end
    local editModeValue = addon.EditMode.GetSetting(frame, setting.settingId)
    if editModeValue == nil then return false end
    local initialEditModeValue = editModeValue

    local dbValue
    -- Convert Edit Mode value to the value addon DB expects
    if settingId == "orientation" then
        dbValue = (editModeValue == 0) and "H" or "V"
    elseif settingId == "columns" then
        if type(component.id) == "string" and component.id:match("^actionBar%d$") then
            -- Action Bars: back-sync #Rows/Columns from the NumRows setting
            local rowsSetting = ResolveSettingId(frame, "num_rows")
            local v = rowsSetting and addon.EditMode.GetSetting(frame, rowsSetting) or editModeValue
            dbValue = math.max(1, math.min(4, tonumber(v) or 1))
        else
            -- Cooldown Viewer: standard 1..20 columns/rows
            dbValue = math.max(1, math.min(20, tonumber(editModeValue) or 12))
        end
    elseif settingId == "numIcons" then
        local iconsSetting = ResolveSettingId(frame, "num_icons")
        local v = iconsSetting and addon.EditMode.GetSetting(frame, iconsSetting) or editModeValue
        dbValue = math.max(6, math.min(12, tonumber(v) or 12))
    elseif settingId == "iconWrap" then
        -- Decode Icon Wrap 0/1 index back into semantic value based on orientation:
        --  Horizontal: 0=Down, 1=Up
        --  Vertical:   0=Left, 1=Right
        -- NOTE: For Aura Frame we may have just performed a Scoot-initiated
        -- orientation remap in AceDB. In that narrow case, the settings panel
        -- marks component._skipNextAuraBackSync and we skip this readback once
        -- to avoid clobbering the freshly remapped DB state with a stale EM snapshot.
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        if sysEnum and frame.system == sysEnum.AuraFrame and component._skipNextAuraBackSync then
            component._skipNextAuraBackSync = nil
            return false
        end

        local o = component.db.orientation or "H"
        local v = tonumber(editModeValue) or 0
        if o == "H" then
            dbValue = (v == 1) and "up" or "down"
        else
            dbValue = (v == 1) and "right" or "left"
        end
    elseif component and component.id == "microBar" and settingId == "direction" then
        -- Micro Bar: 0 = default (Right/Up), 1 = reverse (Left/Down)
        setting.settingId = setting.settingId or 1
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        local orientation = component.db.orientation or "H"
        if orientation == "H" then
            dbValue = (tonumber(v) == 1) and "left" or "right"
        else
            dbValue = (tonumber(v) == 1) and "down" or "up"
        end
        if component.db[settingId] ~= dbValue then component.db[settingId] = dbValue return true end
        return false
    elseif settingId == "direction" then
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        if sysEnum and frame.system == sysEnum.AuraFrame then
            if component._skipNextAuraBackSync then
                component._skipNextAuraBackSync = nil
                return false
            end
            -- Aura Frame: decode 0/1 index according to current orientation:
            --  Horizontal: 0=Left,  1=Right
            --  Vertical:   0=Up,    1=Down
            local orientation = component.db.orientation or "H"
            local v = tonumber(editModeValue) or 0
            if orientation == "H" then
                dbValue = (v == 1) and "right" or "left"
            else
                dbValue = (v == 1) and "up" or "down"
            end
        else
            -- Default mapping used by Cooldown Viewer / Action Bars (orientation-aware)
            local orientation = component.db.orientation or "H"
            if orientation == "H" then
                dbValue = (editModeValue == 1) and "right" or "left"
            else
                dbValue = (editModeValue == 1) and "up" or "down"
            end
        end
    elseif settingId == "iconPadding" then
        -- Library returns raw value; clamp per system:
        --  - Cooldown Viewer / Action Bars / Tracked Bars: 2–14
        --  - Aura Frame (Buffs/Debuffs): 5–15
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        local v = tonumber(editModeValue)
        if sysEnum and frame and frame.system == sysEnum.AuraFrame then
            if not v then v = 10 end
            if v < 5 then v = 5 elseif v > 15 then v = 15 end
        else
            if not v then v = 2 end
            if v < 2 then v = 2 elseif v > 14 then v = 14 end
        end
        dbValue = v
    elseif settingId == "iconLimit" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_limit") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        if v == nil then return false end
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        local minV, maxV = 1, 32
        if sysEnum and frame and frame.system == sysEnum.AuraFrame then
            local isBuffFrame = frame == _G.BuffFrame
            minV = isBuffFrame and 2 or 1
            maxV = isBuffFrame and 32 or 16
        end
        v = tonumber(v) or minV
        v = math.floor(v + 0.5)
        if v < minV then v = minV elseif v > maxV then v = maxV end
        dbValue = v
    elseif settingId == "iconSize" then
        -- Resolve id for non-CDM systems and adapt index-vs-raw semantics.
        -- LibEditModeOverride converts index-based sliders back to raw for callers when
        -- SliderIsIndexBased returns true, so most systems will simply return 50–200 here.
        -- For Aura Frame we additionally sample the live iconScale, which is authoritative.
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        if sysEnum and frame and frame.system == sysEnum.AuraFrame and frame.AuraContainer and frame.AuraContainer.iconScale then
            -- Aura Frame: derive percent directly from the live iconScale on the AuraContainer.
            local scale = tonumber(frame.AuraContainer.iconScale) or 1
            local pct = math.floor((scale * 100) + 0.5)
            if pct < 50 then pct = 50 elseif pct > 200 then pct = 200 end
            dbValue = pct
            if (component.id == "buffs" or component.id == "debuffs") and _AuraBackfillDebugEnabled() then
                _AuraBackfillLog("Sync iconSize: AuraContainer.iconScale=%.3f -> pct=%s (editModeValue=%s)", scale or 0, tostring(pct), tostring(initialEditModeValue))
            end
        else
            setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_size") or setting.settingId
            local raw = addon.EditMode.GetSetting(frame, setting.settingId)
            local v = tonumber(raw) or tonumber(editModeValue) or 100

            -- Heuristic: if the value looks like an index (0–15), convert to 50–200; otherwise
            -- assume it is already a raw percent.
            if v <= 15 then
                dbValue = (v * 10) + 50
            else
                dbValue = v
            end
            if (component.id == "buffs" or component.id == "debuffs") and _AuraBackfillDebugEnabled() then
                _AuraBackfillLog("Sync iconSize: LEO raw=%s editModeValue=%s -> dbValue=%s", tostring(raw), tostring(initialEditModeValue), tostring(dbValue))
            end
        end
    elseif settingId == "size" or settingId == "mapSize" then
        -- Minimap Size: 50-200%, step 10, index-based
        -- Read value via LibEditModeOverride which handles index-to-raw conversion
        setting.settingId = setting.settingId or ResolveSettingId(frame, "size") or setting.settingId
        local raw = addon.EditMode.GetSetting(frame, setting.settingId)
        local v = tonumber(raw) or tonumber(editModeValue) or 100
        -- Heuristic: if the value looks like an index (0–15), convert to 50–200
        if v <= 15 then
            dbValue = (v * 10) + 50
        else
            dbValue = v
        end
        if dbValue < 50 then dbValue = 50 elseif dbValue > 200 then dbValue = 200 end
    elseif settingId == "barWidth" then
        -- Tracked Bars Bar Width Scale: 50-200%, step 1, index-based
        setting.settingId = setting.settingId or ResolveSettingId(frame, "bar_width_scale") or setting.settingId
        local raw = addon.EditMode.GetSetting(frame, setting.settingId)
        local v = tonumber(raw) or tonumber(editModeValue) or 100
        -- Heuristic: if the value looks like an index (0–150), convert to 50–200
        if v <= 150 and v >= 0 then
            -- Could be index; check if LEO already converted. If raw < 50, definitely an index.
            if v < 50 then
                dbValue = v + 50
            else
                dbValue = v
            end
        else
            dbValue = v
        end
        if dbValue < 50 then dbValue = 50 elseif dbValue > 200 then dbValue = 200 end
    elseif settingId == "opacity" then
        -- Read RAW percent. Cooldown Viewer uses 50..100; Objective Tracker uses 0..100.
        local resolved = ResolveSettingId(frame, "opacity")
        if resolved then setting.settingId = resolved end
        local v = tonumber(editModeValue)
        if v == nil then return false end
        v = math.floor(v + 0.5)
        if frame and frame.system == 12 then
            if v < 0 then v = 0 elseif v > 100 then v = 100 end
        else
            if v < 50 then v = 50 elseif v > 100 then v = 100 end
        end
        dbValue = v
    elseif component and component.id == "microBar" and (settingId == "menuSize" or settingId == "eyeSize") then
        -- Library returns RAW values when index-based mode is enabled
        setting.settingId = setting.settingId or ((settingId == "menuSize") and 2 or 3)
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        local minV = (settingId == "menuSize") and 70 or 50
        local maxV = (settingId == "menuSize") and 200 or 150
        local step = 5
        v = tonumber(v) or minV
        if v < minV then v = minV elseif v > maxV then v = maxV end
        v = minV + math.floor(((v - minV) / step) + 0.5) * step
        dbValue = v
    elseif settingId == "visibilityMode" then
        -- 0 = always, 1 = only in combat, 2 = hidden
        setting.settingId = setting.settingId or ResolveSettingId(frame, "visibility") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        if v == nil and frame and type(frame.visibleSetting) ~= "nil" then v = frame.visibleSetting end
        if v == nil then return false end
        if v == 1 then dbValue = "combat" elseif v == 2 then dbValue = "never" else dbValue = "always" end
    elseif settingId == "barVisibility" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "visibility") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        if v == nil and frame and type(frame.visibleSetting) ~= "nil" then v = frame.visibleSetting end
        if v == nil then return false end
        if v == 1 then dbValue = "combat" elseif v == 2 then dbValue = "not_in_combat" elseif v == 3 then dbValue = "hidden" else dbValue = "always" end
    elseif settingId == "hideBarArt" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "hide_bar_art") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        dbValue = (tonumber(v) or 0) == 1 and true or false
    elseif settingId == "hideBarScrolling" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "hide_bar_scrolling") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        dbValue = (tonumber(v) or 0) == 1 and true or false
    elseif settingId == "alwaysShowButtons" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "always_show_buttons") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        dbValue = (tonumber(v) or 0) == 1 and true or false
    elseif settingId == "showTimer" then
        -- Back-sync from Edit Mode: 1/0 -> true/false
        dbValue = (tonumber(editModeValue) or 0) == 1 and true or false
    elseif settingId == "showTooltip" then
        -- Back-sync from Edit Mode: 1/0 -> true/false
        dbValue = (tonumber(editModeValue) or 0) == 1 and true or false
    elseif settingId == "hideWhenInactive" then
        -- Back-sync from Edit Mode: 1/0 -> true/false
        dbValue = (tonumber(editModeValue) or 0) == 1 and true or false
    elseif settingId == "displayMode" then
        -- Back-sync from Edit Mode dropdown to addon values: 0=both,1=icon,2=name (fallback assumption)
        setting.settingId = setting.settingId or ResolveSettingId(frame, "bar_content") or ResolveSettingId(frame, "display_mode") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        if v == 1 then dbValue = "icon" elseif v == 2 then dbValue = "name" else dbValue = "both" end
        if component.db[settingId] ~= dbValue then component.db[settingId] = dbValue return true end
        return false
    elseif component and component.id == "damageMeter" then
        -- DamageMeter-specific back-sync handling
        if settingId == "showSpecIcon" or settingId == "showClassColor" then
            -- Checkbox: 1/0 -> boolean
            dbValue = (tonumber(editModeValue) or 0) == 1
        elseif settingId == "frameWidth" then
            -- Frame Width slider: snap to step 10, range 300-600
            local v = tonumber(editModeValue) or 300
            v = math.floor((v - 300) / 10 + 0.5) * 10 + 300
            if v < 300 then v = 300 elseif v > 600 then v = 600 end
            dbValue = v
        elseif settingId == "frameHeight" then
            -- Frame Height slider: snap to step 10, range 120-400
            local v = tonumber(editModeValue) or 200
            v = math.floor((v - 120) / 10 + 0.5) * 10 + 120
            if v < 120 then v = 120 elseif v > 400 then v = 400 end
            dbValue = v
        elseif settingId == "barHeight" then
            -- Bar Height slider: snap to step 1, range 18-40
            local v = tonumber(editModeValue) or 20
            v = math.floor(v + 0.5)
            if v < 18 then v = 18 elseif v > 40 then v = 40 end
            dbValue = v
        elseif settingId == "padding" then
            -- Padding slider: snap to step 1, range 2-10
            local v = tonumber(editModeValue) or 4
            v = math.floor(v + 0.5)
            if v < 2 then v = 2 elseif v > 10 then v = 10 end
            dbValue = v
        elseif settingId == "opacity" then
            -- Opacity slider: snap to step 5, range 50-100
            local v = tonumber(editModeValue) or 100
            v = math.floor((v - 50) / 5 + 0.5) * 5 + 50
            if v < 50 then v = 50 elseif v > 100 then v = 100 end
            dbValue = v
        elseif settingId == "background" then
            -- Background Opacity slider: snap to step 5, range 0-100
            local v = tonumber(editModeValue) or 80
            v = math.floor(v / 5 + 0.5) * 5
            if v < 0 then v = 0 elseif v > 100 then v = 100 end
            dbValue = v
        elseif settingId == "textSize" then
            -- Text Size slider: snap to step 10, range 50-150
            local v = tonumber(editModeValue) or 100
            v = math.floor((v - 50) / 10 + 0.5) * 10 + 50
            if v < 50 then v = 50 elseif v > 150 then v = 150 end
            dbValue = v
        elseif settingId == "style" or settingId == "visibility" then
            -- Dropdowns: 0, 1, 2
            local v = tonumber(editModeValue) or 0
            if v < 0 then v = 0 elseif v > 2 then v = 2 end
            dbValue = v
        else
            dbValue = tonumber(editModeValue) or 0
        end
    else
        dbValue = tonumber(editModeValue) or 0
    end

    if component.db[settingId] ~= dbValue then
        if (component.id == "buffs" or component.id == "debuffs") and settingId == "iconSize" and _AuraBackfillDebugEnabled() then
            _AuraBackfillLog("Sync result: updating component.db.iconSize from %s to %s", tostring(component.db[settingId]), tostring(dbValue))
        end
        component.db[settingId] = dbValue
        if settingId == "iconSize" and component and (component.id == "buffs" or component.id == "debuffs") then
            local pending = component._pendingAuraIconSizeTarget
            if pending and math.abs((tonumber(dbValue) or 0) - pending) <= 0.5 then
                component._pendingAuraIconSizeTarget = nil
                component._pendingAuraIconSizeExpiry = nil
            end
        end
        -- Notify v2 UI panel if available
        if addon and addon.UI and addon.UI.SettingsPanel and type(addon.UI.SettingsPanel.HandleEditModeBackSync) == "function" then
            addon.UI.SettingsPanel:HandleEditModeBackSync(component.id, settingId)
        end
        return true -- Indicates a change was made
    end
    if (component.id == "buffs" or component.id == "debuffs") and settingId == "iconSize" and _AuraBackfillDebugEnabled() then
        _AuraBackfillLog("Sync result: no change (component.db.iconSize already %s)", tostring(dbValue))
    end
    return false
end
-- Syncs the frame's position from Edit Mode to the addon DB
function addon.EditMode.SyncComponentPositionFromEditMode(component)
    if not component or not component.frameName then
        return false
    end
    if component.disablePositionSync then
        return false
    end
    local hasPositionSettings = component.settings
        and component.settings.positionX
        and component.settings.positionY
    if not hasPositionSettings then
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        return false
    end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        return false
    end
    local frame = _G[component.frameName]
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return false end

    local offsetX, offsetY
    if frame.GetCenter and UIParent and UIParent.GetCenter then
        local okFrame, fx, fy = pcall(frame.GetCenter, frame)
        local okParent, ux, uy = pcall(UIParent.GetCenter, UIParent)
        if fx and fy and ux and uy then
            offsetX = roundPositionValue(fx - ux)
            offsetY = roundPositionValue(fy - uy)
        end
    end

    if offsetX == nil or offsetY == nil then return false end

    -- If this position matches a very recent Scoot-authored write (e.g., from
    -- the X/Y numeric text inputs), skip writing it back into the DB. This
    -- avoids a redundant Settings row reinitialization that would otherwise
    -- steal focus from the text box shortly after the user edits it.
    local recent = component._recentPositionWrite
    if recent and (recent.x ~= nil and recent.y ~= nil) then
        local now = GetTime()
        if now and recent.time and (now - recent.time) <= 0.6 then
            if recent.x == offsetX and recent.y == offsetY then
                return false
            end
        end
    end

    local changed = false
    if component.db.positionX ~= offsetX then
        component.db.positionX = offsetX
        changed = true
    end
    if component.db.positionY ~= offsetY then
        component.db.positionY = offsetY
        changed = true
    end

    return changed
end

function addon.EditMode.ResetComponentPositionToDefault(component)
    if not component or not component.frameName then
        return false, "missing_component"
    end

    local frame = _G[component.frameName]
    if not frame then
        return false, "frame_missing"
    end

    if addon.EditMode and addon.EditMode.LoadLayouts then
        pcall(addon.EditMode.LoadLayouts)
    end

    local usedSystemReset = false
    if type(frame.ResetToDefaultPosition) == "function" then
        local ok = pcall(frame.ResetToDefaultPosition, frame)
        if ok then
            usedSystemReset = true
        end
    end

    if not usedSystemReset then
        local preset = _G.EditModePresetLayoutManager
        if preset and preset.GetModernSystemAnchorInfo and frame.system and frame.systemIndex then
            local anchorInfo = preset:GetModernSystemAnchorInfo(frame.system, frame.systemIndex)
            if anchorInfo then
                local relativeTo = anchorInfo.relativeTo
                if type(relativeTo) == "string" then
                    relativeTo = _G[relativeTo]
                end
                if not relativeTo then
                    relativeTo = UIParent
                end
                addon.EditMode.ReanchorFrame(frame,
                    anchorInfo.point or "CENTER",
                    relativeTo,
                    anchorInfo.relativePoint or "CENTER",
                    anchorInfo.offsetX or 0,
                    anchorInfo.offsetY or 0)
                usedSystemReset = true
            end
        end
        if not usedSystemReset then
            return false, "anchor_unavailable"
        end
    end

    local function syncPosition()
        if addon.EditMode and addon.EditMode.SyncComponentPositionFromEditMode then
            addon.EditMode.SyncComponentPositionFromEditMode(component)
        end
    end

    syncPosition()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, syncPosition)
    end

    if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end

    return true
end

function addon.EditMode.ResetUnitFramePosition(unit)
    if type(unit) ~= "string" then
        return false, "missing_unit"
    end

    if addon.EditMode and addon.EditMode.LoadLayouts then
        pcall(addon.EditMode.LoadLayouts)
    end

    local frame = _GetUnitFrameForUnit(unit)
    if not frame then
        return false, "frame_missing"
    end

    local resetOk = false
    if type(frame.ResetToDefaultPosition) == "function" then
        resetOk = pcall(frame.ResetToDefaultPosition, frame) or false
    end

    if not resetOk then
        local preset = _G.EditModePresetLayoutManager
        if preset and preset.GetModernSystemAnchorInfo and frame.system and frame.systemIndex then
            local anchorInfo = preset:GetModernSystemAnchorInfo(frame.system, frame.systemIndex)
            if anchorInfo then
                local relativeTo = anchorInfo.relativeTo
                if type(relativeTo) == "string" then
                    relativeTo = _G[relativeTo]
                end
                if not relativeTo then
                    relativeTo = UIParent
                end
                addon.EditMode.ReanchorFrame(
                    frame,
                    anchorInfo.point or "CENTER",
                    relativeTo,
                    anchorInfo.relativePoint or "CENTER",
                    anchorInfo.offsetX or 0,
                    anchorInfo.offsetY or 0
                )
                resetOk = true
            end
        end

        if not resetOk then
            return false, "anchor_unavailable"
        end
    end

    if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end

    return true
end

--[[----------------------------------------------------------------------------
    Initialization and Event Handling
----------------------------------------------------------------------------]]--

-- Centralized helper to run all back-sync operations
function addon.EditMode.RefreshSyncAndNotify(origin)
    if LEO and LEO.IsReady and LEO:IsReady() and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end

    addon:SyncAllEditModeSettings()

    if origin and addon.EditMode and addon.EditMode.QueueAuraIconSizeBackfill then
        local lowerOrigin = (type(origin) == "string") and _lower(origin) or ""
        if (lowerOrigin:find("savelayouts", 1, true) or lowerOrigin:find("editmodeexit", 1, true)) and lowerOrigin:find("pass3", 1, true) then
            local delay = 0.35
            if lowerOrigin:find("editmodeexit", 1, true) then
                delay = 0.25
            end
            for _, auraId in ipairs({ "buffs", "debuffs" }) do
                addon.EditMode.QueueAuraIconSizeBackfill(auraId, {
                    delay = delay,
                    origin = origin,
                    retryDelays = { 0.35, 0.75 },
                })
            end
        end
    end

    if addon and addon.Profiles and addon.Profiles.RefreshFromEditMode then
        addon.Profiles:RefreshFromEditMode(origin)
    end

    -- Settings list is not refreshed here; routine Edit Mode saves are reflected
    -- via control bindings and per-row helpers to avoid right-pane flicker.

    if addon._dbgSync and origin then
        print("Scoot RefreshSyncAndNotify origin=" .. tostring(origin))
    end
end
