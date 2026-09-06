-- core.lua - Edit Mode integration helpers and setting resolution

local addonName, addon = ...

-- Central suppression check (used only during short post-copy window)
local function _ShouldSuppressWrites()
    local prof = addon and addon.Profiles
    if not prof or not prof.IsPostCopySuppressed then return false end
    return prof:IsPostCopySuppressed()
end
local function _SafePCall(method, frame, useSecure)
    if not (frame and type(method) == "string") then return end
    local fn = frame[method]
    if type(fn) ~= "function" then return end
    if useSecure then
        securecallfunction(fn, frame)
    else
        pcall(fn, frame)
    end
end

-- Weak-key lookup table to avoid writing properties to Blizzard frames
-- (which would taint them and cause secret value errors during Edit Mode operations)
local editModeState = setmetatable({}, { __mode = "k" })

local function getEditModeState(frame)
    if not frame then return nil end
    if not editModeState[frame] then
        editModeState[frame] = {}
    end
    return editModeState[frame]
end

addon.EditMode = {}

-- OPT-28: Event-driven Edit Mode state flag. Set true on EditMode.Enter,
-- false on EditMode.Exit. Eliminates pcall + Blizzard API checks from the
-- hot-path guard that runs in every hook callback (~106 call sites).
local editModeActiveState = false

local LEO = LibStub("LibEditModeOverride-1.0")

-- Cache for resolved Edit Mode setting IDs per system
local _resolvedSettingIdCache = {}

local function _lower(s)
    if type(s) ~= "string" then return "" end
    return string.lower(s)
end

--[[----------------------------------------------------------------------------
    Copy helpers (Edit Mode only)
----------------------------------------------------------------------------]]--
-- Copy Unit Frame "Frame Size (Scale)" from one unit to another.
-- Allowed units: "Player", "Target", "Focus". Pet returns success (no-op) because
-- Blizzard does not expose a frame size setting for the pet frame.
-- Returns true on success; false and an error key on failure.
function addon.EditMode.CopyUnitFrameFrameSize(sourceUnit, destUnit)
    local function norm(u)
        if type(u) ~= "string" then return nil end
        u = string.lower(u)
        if u == "player" then return "Player" end
        if u == "target" then return "Target" end
        if u == "focus"  then return "Focus" end
        if u == "pet"    then return "Pet" end
    end
    local src = norm(sourceUnit)
    local dst = norm(destUnit)
    if not src or not dst then return false, "invalid_unit" end
    if src == dst then return false, "same_unit" end

    -- Pet frame size is managed internally by Blizzard and does not expose a
    -- configurable Frame Size setting. Treat Pet copy requests as a no-op so
    -- the broader copy flow can continue without surfacing an error.
    if src == "Pet" or dst == "Pet" then
        return true
    end

    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    local UFSetting = _G.Enum and _G.Enum.EditModeUnitFrameSetting
    if not (mgr and EM and EMSys and UFSetting and mgr.GetRegisteredSystemFrame) then return false, "env_unavailable" end

    local srcFrame = addon.GetEditModeUnitFrame(src)
    local dstFrame = addon.GetEditModeUnitFrame(dst)
    if not srcFrame or not dstFrame then return false, "frame_missing" end

    -- Read source Frame Size; library is configured to return RAW (100..200)
    local sizeSetting = UFSetting.FrameSize
    local raw = addon.EditMode.GetSetting(srcFrame, sizeSetting)
    if raw == nil then return false, "no_source_value" end
    local v = tonumber(raw) or 100
    -- Safety: convert index 0..20 to raw 100..200 if observed
    if v <= 20 then v = 100 + (v * 5) end
    if v < 100 then v = 100 elseif v > 200 then v = 200 end

    -- Focus destination requires Use Larger Frame to be enabled
    if dst == "Focus" then
        local useLarger = addon.EditMode.GetSetting(dstFrame, UFSetting.UseLargerFrame)
        if not useLarger or tonumber(useLarger) == 0 then
            return false, "focus_requires_larger"
        end
    end

    -- Write to destination and persist via centralized helper (with light panel suppression)
    if addon.EditMode and addon.EditMode.WriteSetting then
        addon.EditMode.WriteSetting(dstFrame, sizeSetting, v, {
            suspendDuration = 0.25,
        })
    else
        addon.EditMode.SetSetting(dstFrame, sizeSetting, v)
        if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
    end
    return true
end

-- Discover the numeric setting id at runtime to avoid stale hardcodes
local function ResolveSettingId(frame, logicalKey)
    if not frame or not frame.system or not _G.EditModeSettingDisplayInfoManager then return nil end
    -- Ensure layouts are loaded so the display info table is populated
    -- IMPORTANT: Only call LoadLayouts if not already loaded to avoid cascade of calls
    if LEO and LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then
        if addon and addon.EditMode and addon.EditMode.LoadLayouts then addon.EditMode.LoadLayouts() end
    end
    -- Prefer stable enum constants only for Cooldown Viewer systems
    --
    -- Callers use both snake_case ("icon_size") and camelCase ("iconSize").
    -- Both variants must be handled; missing one causes silent save failures.
    --
    local EM = _G.Enum and _G.Enum.EditModeCooldownViewerSetting
    if EM and frame and frame.system == (_G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeSystem.CooldownViewer) then
        if logicalKey == "visibility" then return EM.VisibleSetting end
        if logicalKey == "show_timer" then return EM.ShowTimer end
        if logicalKey == "show_tooltip" then return EM.ShowTooltips end
        -- No stable enum seen for "Hide when inactive"; fall through to dynamic resolver
        if logicalKey == "orientation" then return EM.Orientation end
        if logicalKey == "columns" then return EM.IconLimit end
        if logicalKey == "direction" then return EM.IconDirection end
        -- NOTE: Both snake_case and camelCase are required - callers use both conventions
        if logicalKey == "iconSize" or logicalKey == "icon_size" then return EM.IconSize end
        if logicalKey == "iconPadding" or logicalKey == "icon_padding" then return EM.IconPadding end
        if logicalKey == "opacity" then return EM.Opacity end
        if logicalKey == "barWidth" or logicalKey == "bar_width"
           or logicalKey == "barWidthScale" or logicalKey == "bar_width_scale" then return EM.BarWidthScale end
        -- Tracked Bars specific (bar content/display mode)
        if logicalKey == "bar_content" then return EM.BarContent end
    end

    -- Personal Resource Display: stable enum constants (12.0.7+). The PRD exposes
    -- a single system frame (PersonalResourceDisplayFrame) with no index, so a
    -- straight logical-key → enum mapping is enough.
    local prdEM = _G.Enum and _G.Enum.EditModePersonalResourceDisplaySetting
    if prdEM and frame and frame.system == (_G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeSystem.PersonalResourceDisplay) then
        local lk = _lower(logicalKey)
        if lk == "show_bar_text" or lk == "showbartext" then return prdEM.ShowBarText end
        if lk == "show_class_color" or lk == "showclasscolor" then return prdEM.ShowClassColor end
        if lk == "hide_health" or lk == "hidehealth" then return prdEM.HideHealth end
        if lk == "hide_power" or lk == "hidepower" then return prdEM.HidePower end
        if lk == "hide_alt_power" or lk == "hidealtpower" then return prdEM.HideAltPower end
        if lk == "hide_class_info" or lk == "hideclassinfo" then return prdEM.HideClassInfo end
        if lk == "hide_class_info_on_player_frame" or lk == "hideclassinfoonplayerframe" then return prdEM.HideClassInfoOnPlayerFrame end
        if lk == "health_bar_height" or lk == "healthbarheight" then return prdEM.HealthBarHeight end
        if lk == "power_bar_height" or lk == "powerbarheight" then return prdEM.PowerBarHeight end
        if lk == "bar_width" or lk == "barwidth" then return prdEM.BarWidth end
        if lk == "size" then return prdEM.Size end
        if lk == "padding" then return prdEM.Padding end
        if lk == "opacity" then return prdEM.Opacity end
        if lk == "visibility" or lk == "visible_setting" then return prdEM.VisibleSetting end
    end

    local sys = frame.system
    if not sys then return nil end

    -- Objective Tracker: stable numeric IDs (observed in-game via framestack and preset exports).
    -- Keep these as a fast path, but still allow the dynamic scanner to serve as fallback.
    -- System id: 12
    if sys == 12 then
        local lk = _lower(logicalKey)
        if lk == "height" then return 0 end
        if lk == "opacity" then return 1 end
        if lk == "text_size" or lk == "textsize" then return 2 end
    end

    -- Damage Meter: Use enum-based IDs if available, otherwise fall through to dynamic scanner.
    local dmSys = _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeSystem.DamageMeter
    if dmSys and sys == dmSys then
        local lk = _lower(logicalKey)
        local EM = _G.Enum and _G.Enum.EditModeDamageMeterSetting
        if EM then
            if lk == "style" then return EM.Style end
            if lk == "frame_width" or lk == "framewidth" then return EM.FrameWidth end
            if lk == "frame_height" or lk == "frameheight" then return EM.FrameHeight end
            if lk == "bar_height" or lk == "barheight" then return EM.BarHeight end
            if lk == "padding" then return EM.Padding end
            if lk == "opacity" or lk == "transparency" then return EM.Transparency end
            if lk == "background" or lk == "backgroundtransparency" then return EM.BackgroundTransparency end
            if lk == "text_size" or lk == "textsize" then return EM.TextSize end
            if lk == "visibility" then return EM.Visibility end
            if lk == "show_spec_icon" or lk == "showspecicon" then return EM.ShowSpecIcon end
            if lk == "show_class_color" or lk == "showclasscolor" then return EM.ShowClassColor end
        end
    end

    -- Minimap: Use enum-based IDs
    local minimapSys = _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeSystem.Minimap
    if minimapSys and sys == minimapSys then
        local lk = _lower(logicalKey)
        local EM = _G.Enum and _G.Enum.EditModeMinimapSetting
        if EM then
            if lk == "size" or lk == "mapsize" or lk == "map_size" then return EM.Size end
            if lk == "header_underneath" or lk == "headerunderneath" then return EM.HeaderUnderneath end
            if lk == "rotate_minimap" or lk == "rotateminimap" then return EM.RotateMinimap end
        end
    end

    local auraSystem = _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeSystem.AuraFrame
    local cacheKey = logicalKey
    if sys == auraSystem then
        local frameKey
        if frame == _G.BuffFrame then
            frameKey = "buff"
        elseif frame == _G.DebuffFrame then
            frameKey = "debuff"
        else
            frameKey = (frame and frame.GetName and frame:GetName()) or tostring(frame)
        end
        cacheKey = (frameKey or "frame") .. "::" .. tostring(logicalKey)
    end

    _resolvedSettingIdCache[sys] = _resolvedSettingIdCache[sys] or {}
    if _resolvedSettingIdCache[sys][cacheKey] ~= nil then
        return _resolvedSettingIdCache[sys][cacheKey]
    end

    local entries = _G.EditModeSettingDisplayInfoManager.systemSettingDisplayInfo and _G.EditModeSettingDisplayInfoManager.systemSettingDisplayInfo[sys]
    if type(entries) ~= "table" then return nil end

    local lk = _lower(logicalKey)

    local auraEnum = _G.Enum and _G.Enum.EditModeAuraFrameSetting
    if auraEnum and sys == auraSystem then
        local id
        if lk == "orientation" then
            id = auraEnum.Orientation
        elseif lk == "icon_wrap" or lk == "wrap" then
            id = auraEnum.IconWrap
        elseif lk == "icon_direction" or lk == "direction" then
            id = auraEnum.IconDirection
        elseif lk == "icon_size" then
            id = auraEnum.IconSize
        elseif lk == "icon_padding" then
            id = auraEnum.IconPadding
        elseif lk == "icon_limit" or lk == "iconlimit" or lk == "aura_icon_limit" then
            if frame == _G.BuffFrame then
                id = auraEnum.IconLimitBuffFrame
            elseif frame == _G.DebuffFrame then
                id = auraEnum.IconLimitDebuffFrame
            end
        end
        if id ~= nil then
            _resolvedSettingIdCache[sys][cacheKey] = id
            return id
        end
    end
    local pick
    for _, setup in ipairs(entries) do
        local nm = _lower(setup.name or "")
        local tp = setup.type
        if lk == "visibility" then
            if tp == Enum.EditModeSettingDisplayType.Dropdown then
                local count = 0
                if type(setup.options) == "table" then for _ in pairs(setup.options) do count = count + 1 end end
                -- Accept both 3-option (CDM) and 4-option (Action Bars 2-8) dropdowns whose name includes visibility/visible
                if nm:find("visibility", 1, true) or nm:find("visible", 1, true) or count == 3 or count == 4 then
                    pick = pick or setup
                end
            end
        elseif lk == "opacity" then
            if tp == Enum.EditModeSettingDisplayType.Slider then
                -- Identify by typical 50..100 range or name containing "opacity"
                local minV = tonumber(setup.minValue)
                local maxV = tonumber(setup.maxValue)
                if (minV == 50 and maxV == 100) or nm:find("opacity", 1, true) then
                    pick = pick or setup
                end
            end
        elseif lk == "height" then
            if tp == Enum.EditModeSettingDisplayType.Slider then
                if nm:find("height", 1, true) then
                    pick = pick or setup
                end
            end
        elseif lk == "text_size" or lk == "textsize" then
            if tp == Enum.EditModeSettingDisplayType.Slider then
                if (nm:find("text", 1, true) and nm:find("size", 1, true)) or nm:find("font", 1, true) then
                    pick = pick or setup
                end
            end
        elseif lk == "bar_content" or lk == "display_mode" then
            if tp == Enum.EditModeSettingDisplayType.Dropdown then
                -- 3-way dropdown; look for name including display/content
                local count = 0
                if type(setup.options) == "table" then for _ in pairs(setup.options) do count = count + 1 end end
                if count == 3 and (nm:find("display", 1, true) or nm:find("content", 1, true)) then
                    pick = pick or setup
                end
            end
        elseif lk == "show_timer" or lk == "showtimer" then
            if tp == Enum.EditModeSettingDisplayType.Checkbox and (nm:find("timer", 1, true) or nm:find("countdown", 1, true)) then pick = pick or setup end
        elseif lk == "show_tooltip" or lk == "showtooltip" or lk == "tooltips" then
            if tp == Enum.EditModeSettingDisplayType.Checkbox and nm:find("tooltip", 1, true) then pick = pick or setup end
        elseif lk == "hide_when_inactive" or lk == "hideinactive" or lk == "inactive" then
            if tp == Enum.EditModeSettingDisplayType.Checkbox and (nm:find("inactive", 1, true) or nm:find("hide", 1, true)) then pick = pick or setup end
        elseif lk == "orientation" then
            if tp == Enum.EditModeSettingDisplayType.Dropdown then
                if nm:find("orientation", 1, true) then
                    pick = pick or setup
                end
            end
        elseif lk == "num_rows" then
            if tp == Enum.EditModeSettingDisplayType.Slider then
                if nm:find("row", 1, true) or nm:find("column", 1, true) then
                    pick = pick or setup
                end
            end
        elseif lk == "num_icons" then
            if tp == Enum.EditModeSettingDisplayType.Slider and nm:find("icon", 1, true) then
                pick = pick or setup
            end
        elseif lk == "icon_size" then
            if tp == Enum.EditModeSettingDisplayType.Slider and (nm:find("icon", 1, true) and nm:find("size", 1, true)) then
                pick = pick or setup
            end
        elseif lk == "icon_padding" then
            if tp == Enum.EditModeSettingDisplayType.Slider and nm:find("padding", 1, true) then
                pick = pick or setup
            end
        elseif lk == "icon_limit" or lk == "iconlimit" or lk == "aura_icon_limit" then
            if tp == Enum.EditModeSettingDisplayType.Slider and nm:find("limit", 1, true) and nm:find("icon", 1, true) then
                pick = pick or setup
            end
        elseif lk == "icon_wrap" or lk == "wrap" then
            if tp == Enum.EditModeSettingDisplayType.Dropdown and nm:find("wrap", 1, true) then
                pick = pick or setup
            end
        elseif lk == "icon_direction" or lk == "direction" then
            if tp == Enum.EditModeSettingDisplayType.Dropdown and nm:find("direction", 1, true) and nm:find("icon", 1, true) then
                pick = pick or setup
            end
        elseif lk == "hide_bar_art" then
            if tp == Enum.EditModeSettingDisplayType.Checkbox and nm:find("hide", 1, true) and nm:find("art", 1, true) then
                pick = pick or setup
            end
        elseif lk == "hide_bar_scrolling" then
            if tp == Enum.EditModeSettingDisplayType.Checkbox and nm:find("hide", 1, true) and nm:find("scroll", 1, true) then
                pick = pick or setup
            end
        elseif lk == "always_show_buttons" then
            if tp == Enum.EditModeSettingDisplayType.Checkbox and nm:find("always", 1, true) and nm:find("button", 1, true) then
                pick = pick or setup
            end
        end
    end
    local id = pick and pick.setting or nil
    _resolvedSettingIdCache[sys][cacheKey] = id
    return id
end

-- Expose a safe resolver for other modules (e.g., settings panel builders) that
-- need to query Edit Mode settings for a given component without duplicating
-- the display-info walking logic above.
function addon.EditMode.ResolveSettingIdForComponent(component, logicalKey)
    if not component or not component.frameName then return nil end
    local frame = _G[component.frameName]
    if not frame then return nil end
    return ResolveSettingId(frame, logicalKey)
end

-- Low-level wrappers for LibEditModeOverride
function addon.EditMode.GetSetting(frame, settingId)
    if not LEO or not LEO.GetFrameSetting then return nil end
    if not (LEO.IsReady and LEO:IsReady()) then return nil end
    if LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then
        if LEO.LoadLayouts then
            local ok = pcall(LEO.LoadLayouts, LEO)
            if not ok then return nil end
        else
            return nil
        end
    end
    return LEO:GetFrameSetting(frame, settingId)
end

-- Write a setting to Edit Mode via LibEditModeOverride.
-- Debug logging: Enable with `/run Scoot._dbgEditMode = true` to trace writes.
function addon.EditMode.SetSetting(frame, settingId, value)
    if not LEO or not LEO.SetFrameSetting then
        if addon._dbgEditMode then addon.DebugPrint("|cFFFF0000[EM.SetSetting]|r LEO not available") end
        return nil
    end
    if not (LEO.IsReady and LEO:IsReady()) then
        if addon._dbgEditMode then addon.DebugPrint("|cFFFF0000[EM.SetSetting]|r LEO not ready") end
        return nil
    end
    if LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then
        if LEO.LoadLayouts then
            local ok = pcall(LEO.LoadLayouts, LEO)
            if not ok then
                if addon._dbgEditMode then addon.DebugPrint("|cFFFF0000[EM.SetSetting]|r LoadLayouts failed") end
                return nil
            end
        else
            if addon._dbgEditMode then addon.DebugPrint("|cFFFF0000[EM.SetSetting]|r LoadLayouts unavailable") end
            return nil
        end
    end
    -- Kept off Theme accent: severity mark. Green means the write went through
    -- and is read against the red bail lines above it in the same trace; a red
    -- accent would print a success in the color of a failure.
    if addon._dbgEditMode then
        local frameName = frame and frame:GetName() or "?"
        addon.DebugPrint("|cFF00FF00[EM.SetSetting]|r frame=" .. tostring(frameName) .. " settingId=" .. tostring(settingId) .. " value=" .. tostring(value))
    end
    LEO:SetFrameSetting(frame, settingId, value)
end

function addon.EditMode.ReanchorFrame(frame, point, relativeTo, relativePoint, x, y)
    if not LEO or not LEO.ReanchorFrame then return end
    LEO:ReanchorFrame(frame, point, relativeTo, relativePoint, x, y)
end


-- Edit Mode open/close helpers
-- Guard flag for exiting Edit Mode (set by EditMode.Exit callback, cleared after delay)
addon.EditMode._exitingEditMode = addon.EditMode._exitingEditMode or false

function addon.EditMode.IsEditModeActiveOrOpening()
    -- OPT-28: Three boolean ORs instead of pcall + Blizzard API queries.
    -- editModeActiveState is set/cleared by EditMode.Enter/Exit callbacks.
    -- _openingEditMode/_exitingEditMode cover the 1-second transition windows.
    return addon.EditMode._openingEditMode
        or addon.EditMode._exitingEditMode
        or editModeActiveState
        or false
end

-- Force-clear editModeActiveState if Blizzard confirms Edit Mode is not active.
-- Called by integrity systems (raidframes, partyframes) when they detect the
-- guard may be permanently stuck true — e.g., from a seeding false positive
-- during addon load, or an EditMode.Enter event without a matching Exit.
-- Returns true if the state was reset, false if Edit Mode is genuinely active.
function addon.EditMode.ForceResetIfStuck()
    if not editModeActiveState then return false end
    local mgr = _G.EditModeManagerFrame
    if not mgr then
        editModeActiveState = false
        addon.EditMode._openingEditMode = nil
        addon.EditMode._exitingEditMode = nil
        return true
    end
    -- pcall + explicit == true: safe against secret values in 12.0
    local ok1, active = pcall(function() return mgr.editModeActive end)
    if ok1 and active == true then return false end -- genuinely active
    local ok2, shown = pcall(mgr.IsShown, mgr)
    if ok2 and shown == true then return false end  -- genuinely shown
    -- Both checks say not active, but the cached flag says active: stuck
    editModeActiveState = false
    addon.EditMode._openingEditMode = nil
    addon.EditMode._exitingEditMode = nil
    return true
end

function addon.EditMode.MarkOpeningEditMode()
    addon.EditMode._openingEditMode = true
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(1.0, function()
            if addon and addon.EditMode then
                addon.EditMode._openingEditMode = nil
            end
        end)
    end
end

function addon.EditMode.MarkExitingEditMode()
    addon.EditMode._exitingEditMode = true
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(1.0, function()
            if addon and addon.EditMode then
                addon.EditMode._exitingEditMode = nil
            end
        end)
    end
end

function addon.EditMode.OpenEditMode()
    -- Do NOT call UpdateLayoutInfo() here — writing to EditModeManagerFrame
    -- from addon code permanently taints it. The layout cache is refreshed by
    -- the EnterEditMode post-hook instead (after the secure setup completes).

    if addon and addon.EditMode and addon.EditMode.MarkOpeningEditMode then
        addon.EditMode.MarkOpeningEditMode()
    end

    local function doOpen()
        local mgr = _G.EditModeManagerFrame
        local canEnter = true
        if mgr and type(mgr.CanEnterEditMode) == "function" then
            local ok, can = pcall(mgr.CanEnterEditMode, mgr)
            if ok and not can then
                canEnter = false
            end
        end
        if not canEnter then
            if addon and addon.Print then
                addon:Print("Edit Mode cannot be entered right now.")
            end
            return
        end

        if _G.securecallfunction then
            if _G.ShowUIPanel and mgr then
                securecallfunction(_G.ShowUIPanel, mgr)
                return
            end
            if mgr and type(mgr.EnterEditMode) == "function" then
                securecallfunction(mgr.EnterEditMode, mgr)
                return
            end
            if _G.RunBinding then
                securecallfunction(_G.RunBinding, "TOGGLE_EDIT_MODE")
                return
            end
            if _G.SlashCmdList and _G.SlashCmdList["EDITMODE"] then
                securecallfunction(_G.SlashCmdList["EDITMODE"], "")
                return
            end
        end

        if _G.ShowUIPanel and mgr then
            _G.ShowUIPanel(mgr)
        elseif mgr and type(mgr.EnterEditMode) == "function" then
            mgr:EnterEditMode()
        elseif _G.RunBinding then
            _G.RunBinding("TOGGLE_EDIT_MODE")
        elseif _G.SlashCmdList and _G.SlashCmdList["EDITMODE"] then
            _G.SlashCmdList["EDITMODE"]("")
        else
            if addon and addon.Print then
                addon:Print("Use /editmode to open the layout manager.")
            end
        end
    end

    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, doOpen)
    else
        doOpen()
    end
end

--------------------------------------------------------------------------------
-- Closing Edit Mode
--------------------------------------------------------------------------------

-- Past EditModeExit:pass1 (0.1s), before pass2.
local POST_EXIT_DELAY = 0.2
local PENDING_TTL = 8.0

local pendingPostExit, pendingArmedAt

local function ArmPostExit(fn)
    pendingPostExit, pendingArmedAt = fn, GetTime()
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(PENDING_TTL, function()
            if pendingPostExit == fn then pendingPostExit = nil end
        end)
    end
end

-- Fired from EditModeManagerFrame's OnHide (installed in Initialize). HookScript
-- rather than the EditMode.Exit EventRegistry callback, which can no-fire under
-- 12.0.5.
function addon.EditMode._FlushPostExit()
    local fn = pendingPostExit
    pendingPostExit = nil
    if not fn then return end
    if (GetTime() - (pendingArmedAt or 0)) > PENDING_TTL then return end

    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(POST_EXIT_DELAY, fn)
    else
        fn()
    end
end

--- Close Edit Mode, then run onClosed once it has exited.
---
--- Routes through mgr.onCloseCallback rather than a bare HideUIPanel: that is
--- what surfaces Blizzard's Save/Exit/Cancel prompt when there are unsaved layout
--- changes. ExitEditMode calls RevertAllChanges unconditionally, so skipping the
--- prompt would silently discard the user's work. (Scoot's own LibEditMode frame
--- positions are never at risk - they persist at drag-stop, not at layout save.)
---
--- onClosed cannot run synchronously: UIPanel:Show runs RefreshSyncAndNotify,
--- which must not execute inside the ExitEditMode -> UpdateSystems teardown.
function addon.EditMode.CloseEditMode(onClosed)
    local mgr = _G.EditModeManagerFrame
    if not mgr then
        if onClosed then onClosed() end
        return
    end

    local shown = false
    local ok, isShown = pcall(mgr.IsShown, mgr)
    if ok and isShown == true then shown = true end

    if not shown then
        if onClosed then onClosed() end
        return
    end

    if onClosed then ArmPostExit(onClosed) end

    if addon.EditMode.MarkExitingEditMode then
        addon.EditMode.MarkExitingEditMode()
    end

    -- Never write to mgr. securecallfunction mirrors OpenEditMode above; the
    -- HideUIPanel -> OnHide -> ExitEditMode -> UpdateSystems chain is the
    -- documented 12.0 taint cascade, so the secure wrapper matters.
    local cb = mgr.onCloseCallback
    if type(cb) == "function" and _G.securecallfunction then
        pcall(_G.securecallfunction, cb)
    elseif _G.HideUIPanel then
        if _G.securecallfunction then
            pcall(_G.securecallfunction, _G.HideUIPanel, mgr)
        else
            pcall(_G.HideUIPanel, mgr)
        end
    end
end

-- Helper functions
function addon.EditMode.LoadLayouts()
    if not LEO or not LEO.LoadLayouts or not LEO.IsReady then return end
    if not LEO:IsReady() then return end
    if LEO.AreLayoutsLoaded and LEO:AreLayoutsLoaded() then return end
    pcall(LEO.LoadLayouts, LEO)
end

-- Persist Edit Mode settings and trigger visual refresh via deferred SetActiveLayout.
-- Primary "apply settings visually" entry point for Scoot writes.
-- Debug logging: Enable with `/run Scoot._dbgEditMode = true` to trace save calls.
--
-- Scoot-authored Edit Mode writes are only valid when the active AceDB profile and the
-- active Edit Mode layout agree (they are keyed 1:1 by name). They disagree in exactly
-- two situations: a cross-machine login where the account-synced layout differs from
-- this machine's last-used profile, and the post-reload window where the C API still
-- reports the previous session's layout. In both, a write would land data from one
-- profile in another profile's layout, so callers skip. Skipped syncs are retried by
-- the SaveLayouts 3-pass hook once RefreshFromEditMode aligns profile and layout.
function addon.EditMode.ProfileMatchesActiveLayout()
    if not (LEO and LEO.AreLayoutsLoaded and LEO:AreLayoutsLoaded()) then return false end
    local ok, layoutName = pcall(LEO.GetActiveLayout, LEO)
    if not ok or type(layoutName) ~= "string" then return false end
    local prof = addon.db and addon.db.GetCurrentProfile and addon.db:GetCurrentProfile()
    return prof == layoutName
end

-- IMPORTANT: The visual refresh depends on LEO:SaveOnly() calling SetActiveLayout in a
-- deferred context. If settings save but don't apply visually, check:
-- 1. That LEO:SaveOnly() is being called (not suppressed)
-- 2. That layoutInfo.activeLayout is valid (not nil, must be >= 1)
-- 3. That the deferred C_Timer.After callback executes
function addon.EditMode.SaveOnly()
    if not LEO or not LEO.SaveOnly then
        if addon._dbgEditMode then addon.DebugPrint("|cFFFF0000[EM.SaveOnly]|r LEO not available") end
        return
    end
    if _ShouldSuppressWrites() then
        if addon._dbgEditMode then addon.DebugPrint("|cFFFF0000[EM.SaveOnly]|r Suppressed by _ShouldSuppressWrites") end
        return
    end
    if not addon.EditMode.ProfileMatchesActiveLayout() then
        if addon._dbgEditMode then addon.DebugPrint("|cFFFF6600[EM.SaveOnly]|r Skipped: profile ~= active layout") end
        return
    end
    -- Kept off Theme accent: severity mark, same palette as the red and orange
    -- lines above. Green here means the save ran, not that Scoot is speaking.
    if addon._dbgEditMode then addon.DebugPrint("|cFF00FF00[EM.SaveOnly]|r Calling LEO:SaveOnly()") end
    LEO:SaveOnly()
end

-- Centralized write helper for Edit Mode–controlled settings.
-- All Scoot-initiated writes to Edit Mode should flow through this helper
-- so that SaveOnly and panel refresh suppression behave
-- consistently across systems (Cooldown Viewer, Action Bars, Unit Frames, etc.).
--
-- opts:
--   updaters        = { "MethodOnFrame", { frame = otherFrame, method = "Layout" }, ... }
--   suspendDuration = number | nil   -- seconds to suspend panel refresh (optional)
--   skipSave        = boolean | nil  -- when true, do not call SaveOnly()
-- IMPORTANT (taint/combat lockdown):
-- UnitFrames/ActionBars/etc are protected systems. Writing Edit Mode settings during combat can
-- trigger Blizzard layout code that calls protected functions (e.g. PartyFrame:SetSize()) and
-- surface as ADDON_ACTION_BLOCKED blaming Scoot.
--
-- Policy: If in combat, queue the write and apply it immediately after combat ends.
-- One keyed entry on the shared regen drain; the listener is armed only while a
-- write is pending.
local function _QueueCombatWriteFlush()
    addon.Events.RunOutOfCombat(function()
        -- Defer a tick to let Blizzard finish post-combat churn.
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                if addon and addon.EditMode and addon.EditMode.FlushPendingWrites then
                    addon.EditMode.FlushPendingWrites("PLAYER_REGEN_ENABLED")
                end
            end)
        elseif addon and addon.EditMode and addon.EditMode.FlushPendingWrites then
            addon.EditMode.FlushPendingWrites("PLAYER_REGEN_ENABLED")
        end
    end, "EditMode:flushWrites")
end

function addon.EditMode.FlushPendingWrites(origin)
    if not addon or not addon.EditMode then return end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end

    local pending = addon.EditMode._pendingWrites
    if type(pending) ~= "table" then return end
    addon.EditMode._pendingWrites = nil

    -- Re-apply queued writes. These will now run out of combat.
    for _, item in pairs(pending) do
        if type(item) == "table" and item.frame and item.settingId ~= nil then
            addon.EditMode.WriteSetting(item.frame, item.settingId, item.value, item.opts)
        end
    end
end

function addon.EditMode.WriteSetting(frame, settingId, value, opts)
    if not frame or settingId == nil then return end
    if not addon.EditMode or not addon.EditMode.SetSetting then return end

    opts = opts or {}

    -- Refuse writes while the AceDB profile and the active Edit Mode layout disagree
    -- (cross-machine login, post-reload stale window). Checked before the combat queue
    -- so a doomed write is never queued for post-combat replay.
    if not opts.allowLayoutMismatch and not addon.EditMode.ProfileMatchesActiveLayout() then
        if addon._dbgEditMode then addon.DebugPrint("|cFFFF6600[EM.WriteSetting]|r Skipped: profile ~= active layout") end
        return
    end

    -- DEPRECATION WARNING: 'updaters' causes taint by calling methods on system frames.
    -- Visual updates happen via deferred SetActiveLayout() in SaveOnly().
    if opts.updaters and addon._dbgEditMode then
        addon.DebugPrint("|cFFFF0000[EM.WriteSetting] WARNING: 'updaters' option is deprecated in 12.0+|r")
        addon.DebugPrint("|cFFFF0000  Causes taint - remove updaters and rely on deferred SetActiveLayout()|r")
    end

    -- Never try Edit Mode writes during combat.
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        addon.EditMode._pendingWrites = addon.EditMode._pendingWrites or {}

        -- Coalesce by (frame, settingId) so sliders/steppers don't spam queued writes.
        local frameKey = (frame.GetName and frame:GetName()) or tostring(frame)
        local key = tostring(frameKey) .. ":" .. tostring(settingId)
        addon.EditMode._pendingWrites[key] = {
            frame = frame,
            settingId = settingId,
            value = value,
            opts = opts,
        }

        _QueueCombatWriteFlush()
        return
    end

    -- Avoid touching forbidden frames (can happen if Blizzard tears down the system mid-session).
    if frame.IsForbidden and frame:IsForbidden() then
        return
    end

    -- Perform the low-level write
    addon.EditMode.SetSetting(frame, settingId, value)

    -- Run any requested update methods to nudge visuals immediately
    local updaters = opts.updaters
    local useSecureUpdaters = opts.secureUpdaters == true
    if type(updaters) == "table" then
        for _, u in ipairs(updaters) do
            if type(u) == "string" then
                _SafePCall(u, frame, useSecureUpdaters)
            elseif type(u) == "table" then
                local target = u.frame or frame
                local method = u.method
                if target and type(method) == "string" and type(target[method]) == "function" then
                    if useSecureUpdaters then
                        securecallfunction(target[method], target)
                    else
                        pcall(target[method], target)
                    end
                end
            end
        end
    end

    -- Persist layout changes
    if not opts.skipSave and addon.EditMode.SaveOnly then
        addon.EditMode.SaveOnly()
    end
end

-- Convenience: write a Personal Resource Display Edit Mode setting by logical key
-- (e.g. "show_bar_text", "hide_health", "show_class_color"). Resolves
-- PersonalResourceDisplayFrame + the stable enum id, then routes through the
-- centralized, combat-safe WriteSetting path. Skips the write (and its layout
-- rebuild) when the stored value already matches. Returns true if a write was
-- issued or unnecessary, false if the setting could not be resolved.
function addon.EditMode.WritePRDSetting(logicalKey, value, opts)
    local prd = _G.PersonalResourceDisplayFrame
    if not prd or not prd.system then return false end
    if not addon.EditMode.WriteSetting then return false end
    local settingId = ResolveSettingId(prd, logicalKey)
    if settingId == nil then return false end
    -- Avoid a redundant layout rebuild when the value already matches.
    local current = addon.EditMode.GetSetting(prd, settingId)
    if current ~= nil and tonumber(current) == tonumber(value) then return true end
    addon.EditMode.WriteSetting(prd, settingId, value, opts)
    return true
end

function addon.EditMode.IsReady()
    return LEO and LEO.IsReady and LEO:IsReady()
end

function addon.EditMode.HasEditModeSettings(frame)
    if not LEO then return false end
    if not (LEO.IsReady and LEO:IsReady()) then return false end
    if LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then
        if LEO.LoadLayouts then
            local ok = pcall(LEO.LoadLayouts, LEO)
            if not ok then return false end
        else
            return false
        end
    end
    return LEO.HasEditModeSettings and LEO:HasEditModeSettings(frame)
end

--[[----------------------------------------------------------------------------
    State Synchronization Logic
----------------------------------------------------------------------------]]--

-- Back-sync for position
local function roundPositionValue(v)
    v = tonumber(v) or 0
    return v >= 0 and math.floor(v + 0.5) or math.ceil(v - 0.5)
end

--[[----------------------------------------------------------------------------
    Objective Tracker: relayout helper for Text Size changes
----------------------------------------------------------------------------]]--
local function _ForceObjectiveTrackerRelayout(frame, origin)
    if not frame then return end

    local state = getEditModeState(frame)
    if not state then return end

    -- Avoid re-entrancy and avoid calling into module layout code while Blizzard is mid-update
    -- (this can trip internal invariants like AnchorBlock entry counts).
    state.relayoutOrigin = origin or state.relayoutOrigin
    if state.relayoutQueued then return end
    state.relayoutQueued = true

    local timer = _G.C_Timer
    if not (timer and type(timer.After) == "function") then
        state.relayoutQueued = nil
        return
    end

    timer.After(0, function()
        if not frame then return end
        local st = getEditModeState(frame)
        if st then
            st.relayoutQueued = nil
            st.relayoutOrigin = nil
        end

        -- Method calls on ObjectiveTrackerFrame (ForEachModule, MarkDirty, UpdateLayout,
        -- UpdateSystem, Update) REMOVED — calling methods on registered Edit Mode system
        -- frames from addon context permanently taints them. The ExitEditMode flow already
        -- triggers UpdateSystems → UpdateSystem on all frames through Blizzard's clean path.
        -- Trigger a clean C-side rebuild instead.
        if C_EditMode and C_EditMode.GetLayouts and C_EditMode.SetActiveLayout then
            local li = C_EditMode.GetLayouts()
            if li and li.activeLayout then
                pcall(C_EditMode.SetActiveLayout, li.activeLayout)
            end
        end
    end)
end

-- Expose internals for sibling editmode files
addon.EditMode._ResolveSettingId = ResolveSettingId
addon.EditMode._getEditModeState = getEditModeState
addon.EditMode._roundPositionValue = roundPositionValue
addon.EditMode._ForceObjectiveTrackerRelayout = _ForceObjectiveTrackerRelayout

-- Initialize Edit Mode integration
function addon.EditMode.Initialize()
    local function CloseScootSettingsPanelForEditMode()
        -- Invariant: Scoot's settings panel must not remain open while Edit Mode is open.
        -- Keeping both UIs visible creates sync churn (recycled Settings rows, back-sync passes, etc.).
        local panel = addon and addon.UI and addon.UI.SettingsPanel
        if panel then
            panel._closedByEditMode = true
            if panel.frame and panel.frame.IsShown and panel.frame:IsShown() then
                pcall(panel.frame.Hide, panel.frame)
            end
        end
    end

    -- Enable compatibility mode for opacity: treat as index-based in LEO to match client persistence
    local LEO_local = LibStub and LibStub("LibEditModeOverride-1.0")
    if LEO_local and _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeCooldownViewerSetting then
        local sys = _G.Enum.EditModeSystem.CooldownViewer
        local setting = _G.Enum.EditModeCooldownViewerSetting.Opacity
        LEO_local._forceIndexBased = LEO_local._forceIndexBased or {}
        LEO_local._forceIndexBased[sys] = LEO_local._forceIndexBased[sys] or {}
        LEO_local._forceIndexBased[sys][setting] = true
    end

    -- Compatibility: Objective Tracker Height (system 12) appears to be stored as an index internally
    -- (0..N) even though the UI presents raw values (400..1000). Force index-based translation in LEO
    -- so Scoot always reads/writes raw values without bespoke conversions elsewhere.
    do
        local LEO_ot = LibStub and LibStub("LibEditModeOverride-1.0")
        if LEO_ot then
            local sys = 12 -- Objective Tracker
            local displayType = _G.Enum and _G.Enum.EditModeSettingDisplayType
            local mgr = _G.EditModeSettingDisplayInfoManager
            local entries = mgr and mgr.systemSettingDisplayInfo and mgr.systemSettingDisplayInfo[sys]

            local function force(settingId)
                if settingId == nil then return end
                LEO_ot._forceIndexBased = LEO_ot._forceIndexBased or {}
                LEO_ot._forceIndexBased[sys] = LEO_ot._forceIndexBased[sys] or {}
                LEO_ot._forceIndexBased[sys][settingId] = true
            end

            if type(entries) == "table" and displayType and displayType.Slider ~= nil then
                for _, setup in ipairs(entries) do
                    if setup and setup.type == displayType.Slider then
                        local minV = tonumber(setup.minValue)
                        local maxV = tonumber(setup.maxValue)
                        local step = tonumber(setup.stepSize)
                        -- Height slider is observed as 400..1000, step 10 in retail.
                        if minV == 400 and maxV == 1000 and step == 10 then
                            force(setup.setting)
                        end
                        -- Text Size slider is observed as 12..20, step 1 in retail.
                        -- Some clients persist this slider as an index (0..8) internally. Force
                        -- index-based translation so Scoot always reads/writes RAW values.
                        if minV == 12 and maxV == 20 and step == 1 then
                            force(setup.setting)
                        end
                    end
                end
            else
                -- Fallback: expected stable setting id for Height is 0.
                force(0)
                -- Fallback: expected stable setting id for Text Size is 2.
                force(2)
            end
        end
    end
    if not addon._hookedSave and type(_G.C_EditMode) == "table" and type(_G.C_EditMode.SaveLayouts) == "function" then
        hooksecurefunc(_G.C_EditMode, "SaveLayouts", function()
            C_Timer.After(0.0, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("SaveLayouts:pass1") end end)
            C_Timer.After(0.25, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("SaveLayouts:pass2") end end)
            C_Timer.After(0.6, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("SaveLayouts:pass3") end end)
        end)
        addon._hookedSave = true
    end

    if _G.EventRegistry and not addon._editModeCBRegistered then
        local ER = _G.EventRegistry
        if type(ER.RegisterCallback) == "function" then
            ER:RegisterCallback("EditMode.Enter", function()
                -- OPT-28: Set persistent state flag immediately
                editModeActiveState = true
                -- Mark that Edit Mode is entering to suppress addon hooks during the transition
                -- Prevents taint from propagating during Blizzard's frame setup
                if addon and addon.EditMode and addon.EditMode.MarkOpeningEditMode then
                    addon.EditMode.MarkOpeningEditMode()
                end
                -- Do not push on enter; it can cause recursion and frame churn as Blizzard initializes widgets.
                -- Panel closing is enforced via the EditModeManagerFrame:EnterEditMode hook below,
                -- which represents the real user Edit Mode entry path.
            end, addon)
            ER:RegisterCallback("EditMode.Exit", function()
                -- OPT-28: Clear persistent state flag immediately
                editModeActiveState = false
                -- Mark that Edit Mode is exiting to suppress addon hooks during the transition
                -- Prevents taint from propagating during Blizzard's frame setup
                if addon and addon.EditMode and addon.EditMode.MarkExitingEditMode then
                    addon.EditMode.MarkExitingEditMode()
                end

                C_Timer.After(0.1, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("EditModeExit:pass1") end end)
                C_Timer.After(0.5, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("EditModeExit:pass2") end end)
                C_Timer.After(1.0, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("EditModeExit:pass3") end end)

                -- Kept off addon.Refresh: targeted re-applies tied to one Edit Mode exit, not an ordered chain.
                -- Late revalidation for group frame health overlay colors.
                -- Runs after _exitingEditMode clears (1.0s) so all hooks are active.
                -- Clears stale color caches that could cause applyValueBasedColor
                -- to early-return, then forces a full overlay reapply.
                C_Timer.After(1.2, function()
                    if InCombatLockdown and InCombatLockdown() then return end
                    -- Clear color caches so applyValueBasedColor doesn't short-circuit
                    if addon.BarsTextures and addon.BarsTextures.clearColorCache then
                        for i = 1, 5 do
                            local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
                            if bar then addon.BarsTextures.clearColorCache(bar) end
                        end
                        for i = 1, 40 do
                            local bar = _G["CompactRaidFrame" .. i .. "HealthBar"]
                            if bar then addon.BarsTextures.clearColorCache(bar) end
                        end
                    end
                    -- Re-apply overlays (styleHealthOverlay → applyValueBasedColor)
                    if addon.ApplyPartyFrameHealthOverlays then
                        pcall(addon.ApplyPartyFrameHealthOverlays)
                    end
                    if addon.ApplyRaidFrameHealthOverlays then
                        pcall(addon.ApplyRaidFrameHealthOverlays)
                    end
                end)

                -- After Save/Exit, some clients apply the new text size but leave stale block spacing
                -- until another tracker rebuild. Force one relayout pass shortly after exit.
                C_Timer.After(0.15, function()
                    if InCombatLockdown and InCombatLockdown() then return end
                    local frame = _G.ObjectiveTrackerFrame
                    if not frame then return end
                    _ForceObjectiveTrackerRelayout(frame, "EditModeExit")
                    local comp = addon.Components and addon.Components.objectiveTracker
                    if comp and type(comp.ApplyStyling) == "function" then
                        pcall(comp.ApplyStyling, comp)
                    elseif addon and type(addon.ApplyStyles) == "function" then
                        pcall(addon.ApplyStyles, addon)
                    end
                end)
            end, addon)
            addon._editModeCBRegistered = true
        end

        -- OPT-28: Seed the cached state for reload-while-in-Edit-Mode.
        -- EventRegistry callbacks only fire on transitions, so if Edit Mode
        -- was already active before this code ran, the flag would be stale.
        -- pcall + explicit == true: safe against secret values in 12.0
        -- (raw boolean test on mgr.editModeActive can error on secrets).
        do
            local mgr = _G.EditModeManagerFrame
            if mgr then
                local isActive = false
                local ok1, active = pcall(function() return mgr.editModeActive end)
                if ok1 and active == true then isActive = true end
                if not isActive then
                    local ok2, shown = pcall(mgr.IsShown, mgr)
                    if ok2 and shown == true then isActive = true end
                end
                if isActive then
                    editModeActiveState = true
                end
            end
        end

        -- Deferred verification: if seeding set editModeActiveState=true,
        -- re-check 2s later that Edit Mode is still active. Catches
        -- false positives from transient IsShown()/editModeActive during load
        -- or from an EditMode.Enter event without a matching Exit (lock state).
        if editModeActiveState then
            C_Timer.After(2.0, function()
                if not editModeActiveState then return end -- already cleared
                local mgr = _G.EditModeManagerFrame
                if not mgr then
                    editModeActiveState = false
                    return
                end
                local stillActive = false
                local ok1, active = pcall(function() return mgr.editModeActive end)
                if ok1 and active == true then stillActive = true end
                if not stillActive then
                    local ok2, shown = pcall(mgr.IsShown, mgr)
                    if ok2 and shown == true then stillActive = true end
                end
                if not stillActive then
                    editModeActiveState = false
                    addon.EditMode._openingEditMode = nil
                    addon.EditMode._exitingEditMode = nil
                    -- Kept off addon.Refresh: targeted re-applies tied to one Edit Mode exit, not an ordered chain.
                    -- Trigger overlay reapply since hooks may have been suppressed
                    C_Timer.After(0.1, function()
                        if InCombatLockdown and InCombatLockdown() then return end
                        if addon.ApplyRaidFrameHealthOverlays then
                            pcall(addon.ApplyRaidFrameHealthOverlays)
                        end
                        if addon.ApplyRaidFrameHealthBarBorders then
                            pcall(addon.ApplyRaidFrameHealthBarBorders)
                        end
                        if addon.ApplyPartyFrameHealthOverlays then
                            pcall(addon.ApplyPartyFrameHealthOverlays)
                        end
                        if addon.ApplyPartyFrameHealthBarBorders then
                            pcall(addon.ApplyPartyFrameHealthBarBorders)
                        end
                    end)
                end
            end)
        end
    end

    -- Fallback hook for clients/builds that don't fire EventRegistry callbacks reliably.
    -- IMPORTANT: Hook EnterEditMode (not OnShow) to avoid accidentally closing the panel
    -- during the "bounce EditModeManagerFrame" taint-clearing work.
    --
    -- Also handles per-system settings refresh: when Scoot changes Edit Mode
    -- settings (via SaveOnly/skipApply), the C-side storage is updated but the
    -- system frames' internal settingMaps are stale. Fresh data is read from C-side
    -- and call UpdateSystem on each registered frame with the correct per-system
    -- systemInfo, WITHOUT writing to mgr.layoutInfo (which would taint the manager).
    if not addon._editModeClosePanelHooked and type(_G.hooksecurefunc) == "function" then
        local mgr = _G.EditModeManagerFrame
        if mgr and type(mgr.EnterEditMode) == "function" then
            addon._editModeClosePanelHooked = true
            _G.hooksecurefunc(mgr, "EnterEditMode", function()
                if addon and addon.EditMode then
                    addon.EditMode._openingEditMode = nil
                end
                CloseScootSettingsPanelForEditMode()
            end)
        end
    end

    -- Deferred continuation for addon.EditMode.CloseEditMode. OnHide is the
    -- reliable exit signal; the EditMode.Exit EventRegistry callback can no-fire
    -- under 12.0.5.
    if not addon._editModePostExitHooked then
        local mgr = _G.EditModeManagerFrame
        if mgr and mgr.HookScript then
            addon._editModePostExitHooked = true
            mgr:HookScript("OnHide", function()
                if addon and addon.EditMode and addon.EditMode._FlushPostExit then
                    addon.EditMode._FlushPostExit()
                end
            end)
        end
    end

    -- Compatibility: Action Bars Icon Size behaves like an index slider internally on some clients.
    -- Force index-based handling in the embedded LEO so raw 50..200 maps to the correct index.
    local LEO_local2 = LibStub and LibStub("LibEditModeOverride-1.0")
    if LEO_local2 and _G and _G.Enum and _G.Enum.EditModeSystem then
        local candidates = {
            "MainActionBar",
            "MultiBarBottomLeft",
            "MultiBarBottomRight",
            "MultiBarRight",
            "MultiBarLeft",
            "MultiBar5",
            "MultiBar6",
            "MultiBar7",
            "PetActionBar",
        }
        for _, name in ipairs(candidates) do
            local fr = _G[name]
            if fr and addon.EditMode.HasEditModeSettings(fr) then
                local settingId = ResolveSettingId(fr, "icon_size")
                if settingId then
                    local sys = fr.system
                    LEO_local2._forceIndexBased = LEO_local2._forceIndexBased or {}
                    LEO_local2._forceIndexBased[sys] = LEO_local2._forceIndexBased[sys] or {}
                    LEO_local2._forceIndexBased[sys][settingId] = true
                end
            end
        end

        -- Micro Bar (Menu): treat Menu Size and Eye Size as index-based internally
        do
            local micro = _G["MicroMenuContainer"]
            if micro then
                local sys = micro.system or 13
                LEO_local2._forceIndexBased = LEO_local2._forceIndexBased or {}
                LEO_local2._forceIndexBased[sys] = LEO_local2._forceIndexBased[sys] or {}
                -- Known setting ids from runtime dumps
                LEO_local2._forceIndexBased[sys][2] = true -- Menu Size
                LEO_local2._forceIndexBased[sys][3] = true -- Eye Size
            else
                -- Fallback: set by known system id for retail
                local sys = 13
                LEO_local2._forceIndexBased = LEO_local2._forceIndexBased or {}
                LEO_local2._forceIndexBased[sys] = LEO_local2._forceIndexBased[sys] or {}
                LEO_local2._forceIndexBased[sys][2] = true
                LEO_local2._forceIndexBased[sys][3] = true
            end
        end
    end

    -- Treat Unit Frame Frame Size as index-based: Edit Mode stores an index (0..20) while UI presents 100..200.
    do
        local LEO_flag = LibStub and LibStub("LibEditModeOverride-1.0")
        if LEO_flag and _G and _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeUnitFrameSetting then
            local sysUF = _G.Enum.EditModeSystem.UnitFrame
            local settingFS = _G.Enum.EditModeUnitFrameSetting.FrameSize
            LEO_flag._forceIndexBased = LEO_flag._forceIndexBased or {}
            LEO_flag._forceIndexBased[sysUF] = LEO_flag._forceIndexBased[sysUF] or {}
            LEO_flag._forceIndexBased[sysUF][settingFS] = true
        end
    end

    -- Unit Frame Frame Width/Height use ConvertValueDiffFromMin (stored = raw - min).
    -- Force DiffFromMin handling in embedded LEO so callers always read/write RAW (72..144, 36..72).
    do
        local LEO_flag = LibStub and LibStub("LibEditModeOverride-1.0")
        if LEO_flag and _G and _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeUnitFrameSetting then
            local sysUF = _G.Enum.EditModeSystem.UnitFrame
            local settingW = _G.Enum.EditModeUnitFrameSetting.FrameWidth
            local settingH = _G.Enum.EditModeUnitFrameSetting.FrameHeight
            LEO_flag._forceDiffFromMin = LEO_flag._forceDiffFromMin or {}
            LEO_flag._forceDiffFromMin[sysUF] = LEO_flag._forceDiffFromMin[sysUF] or {}
            LEO_flag._forceDiffFromMin[sysUF][settingW] = true
            LEO_flag._forceDiffFromMin[sysUF][settingH] = true
        end
    end

    -- Personal Resource Display sliders (12.0.7+). Size/BarWidth/Padding/Opacity use
    -- ConvertValueDefault (stored index = (raw - min) / step); HealthBarHeight/PowerBarHeight
    -- use ConvertValueDiffFromMin (stored = raw - min). Registering both lets Scoot read and
    -- write UI-facing values (70..150 %, 50..150 %, 0..10, 50..100 %, 10..30 px). The
    -- DiffFromMin flag on PowerBarHeight (id 5) also keeps it out of the library's
    -- CDM-opacity heuristic, which is keyed on setting id 5.
    do
        local LEO_flag = LibStub and LibStub("LibEditModeOverride-1.0")
        if LEO_flag and _G and _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModePersonalResourceDisplaySetting then
            local sysPRD = _G.Enum.EditModeSystem.PersonalResourceDisplay
            local S = _G.Enum.EditModePersonalResourceDisplaySetting
            LEO_flag._forceIndexBased = LEO_flag._forceIndexBased or {}
            LEO_flag._forceIndexBased[sysPRD] = LEO_flag._forceIndexBased[sysPRD] or {}
            LEO_flag._forceDiffFromMin = LEO_flag._forceDiffFromMin or {}
            LEO_flag._forceDiffFromMin[sysPRD] = LEO_flag._forceDiffFromMin[sysPRD] or {}
            if S.Size then LEO_flag._forceIndexBased[sysPRD][S.Size] = true end
            if S.BarWidth then LEO_flag._forceIndexBased[sysPRD][S.BarWidth] = true end
            if S.Padding then LEO_flag._forceIndexBased[sysPRD][S.Padding] = true end
            if S.Opacity then LEO_flag._forceIndexBased[sysPRD][S.Opacity] = true end
            if S.HealthBarHeight then LEO_flag._forceDiffFromMin[sysPRD][S.HealthBarHeight] = true end
            if S.PowerBarHeight then LEO_flag._forceDiffFromMin[sysPRD][S.PowerBarHeight] = true end
        end
    end

    -- Compatibility: Some clients persist Cast Bar Bar Size as an index; treat as index-based to avoid snapping to max.
    do
        local LEO_flag2 = LibStub and LibStub("LibEditModeOverride-1.0")
        if LEO_flag2 and _G and _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeCastBarSetting then
            local sysCB = _G.Enum.EditModeSystem.CastBar
            local settingBS = _G.Enum.EditModeCastBarSetting.BarSize
            LEO_flag2._forceIndexBased = LEO_flag2._forceIndexBased or {}
            LEO_flag2._forceIndexBased[sysCB] = LEO_flag2._forceIndexBased[sysCB] or {}
            LEO_flag2._forceIndexBased[sysCB][settingBS] = true
        end
    end

    -- Register DamageMeter sliders as index-based for proper value conversion
    do
        local LEO = LibStub and LibStub("LibEditModeOverride-1.0")
        if LEO and _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeDamageMeterSetting then
            local sysDM = _G.Enum.EditModeSystem.DamageMeter
            local EM = _G.Enum.EditModeDamageMeterSetting
            LEO._forceIndexBased = LEO._forceIndexBased or {}
            LEO._forceIndexBased[sysDM] = LEO._forceIndexBased[sysDM] or {}
            if EM.FrameWidth then LEO._forceIndexBased[sysDM][EM.FrameWidth] = true end
            if EM.FrameHeight then LEO._forceIndexBased[sysDM][EM.FrameHeight] = true end
            if EM.BarHeight then LEO._forceIndexBased[sysDM][EM.BarHeight] = true end
            if EM.Padding then LEO._forceIndexBased[sysDM][EM.Padding] = true end
            if EM.Transparency then LEO._forceIndexBased[sysDM][EM.Transparency] = true end
            if EM.BackgroundTransparency then LEO._forceIndexBased[sysDM][EM.BackgroundTransparency] = true end
            if EM.TextSize then LEO._forceIndexBased[sysDM][EM.TextSize] = true end
        end
    end
end
