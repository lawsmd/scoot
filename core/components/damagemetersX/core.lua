-- damagemetersX/core.lua - Damage Meters X: session state, overlay management, Edit Mode integration
local addonName, addon = ...

-- Damage Meters Component
-- Targets Blizzard's Damage Meter frame (DamageMeter, Edit Mode system) and provides:
-- - Edit Mode settings: Style, Frame Width/Height, Bar Height, Padding, Opacity, Background, Text Size, Visibility, Show Spec Icon, Show Class Color
-- - Addon-only settings: Bar textures, fonts, colors, borders, etc.
--
-- Zero-Touch invariant:
-- - If the profile has no persisted table for this component, ApplyStyling must do nothing.
-- - Even if the component DB exists due to Edit Mode changes, addon-only styling should only apply
--   when the specific config tables exist.

-- Namespace setup
addon.DamageMetersX = addon.DamageMetersX or {}
local DMX = addon.DamageMetersX

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

local function SafeSetAlpha(frame, alpha)
    if not frame or not frame.SetAlpha then return false end
    return pcall(frame.SetAlpha, frame, alpha)
end

local function SafeSetShown(region, shown)
    if not region then return end
    if region.SetShown then
        pcall(region.SetShown, region, shown and true or false)
        return
    end
    if shown then
        if region.Show then pcall(region.Show, region) end
    else
        if region.Hide then pcall(region.Hide, region) end
    end
end

local PlayerInCombat = addon.Opacity.InCombat

local function GetClassColor(classToken)
    if not classToken then return 1, 1, 1, 1 end
    local r, g, b = addon.GetClassColorRGB(classToken)
    return r or 1, g or 1, b or 1, 1
end

DMX._SafeSetAlpha = SafeSetAlpha
DMX._SafeSetShown = SafeSetShown
DMX._PlayerInCombat = PlayerInCombat
DMX._GetClassColor = GetClassColor

--------------------------------------------------------------------------------
-- JiberishIcons Integration Helpers
--------------------------------------------------------------------------------

local function GetJiberishIcons()
    local JIGlobal = _G.ElvUI_JiberishIcons
    if not JIGlobal or type(JIGlobal) ~= "table" then return nil end
    local JI = JIGlobal[1]
    if not JI then return nil end
    return JI
end

local function IsJiberishIconsAvailable()
    local JI = GetJiberishIcons()
    if not JI then return false end
    if not JI.dataHelper or not JI.dataHelper.class then return false end
    if not JI.mergedStylePacks or not JI.mergedStylePacks.class then return false end
    return true
end

local function GetJiberishIconsStyles()
    local JI = GetJiberishIcons()
    if not JI or not JI.mergedStylePacks or not JI.mergedStylePacks.class then return {} end
    local styles = {}
    for key, data in pairs(JI.mergedStylePacks.class.styles or {}) do
        styles[key] = data.name or key
    end
    return styles
end

-- Export to addon namespace for UI access
addon.IsJiberishIconsAvailable = IsJiberishIconsAvailable
addon.GetJiberishIconsStyles = GetJiberishIconsStyles
DMX._GetJiberishIcons = GetJiberishIcons

--------------------------------------------------------------------------------
-- State Tables
--------------------------------------------------------------------------------

-- Per-window state storage (avoids tainting Blizzard frames with _Scoot* properties)
local windowState = setmetatable({}, { __mode = "k" })  -- Weak keys for GC

local function getWindowState(sessionWindow)
    if not windowState[sessionWindow] then
        windowState[sessionWindow] = {}
    end
    return windowState[sessionWindow]
end

-- Per-element state (icons, status bars, overlays) — avoids writing _scooter* fields
-- directly onto Blizzard child frames which can propagate taint to the parent system frame.
local elementState = setmetatable({}, { __mode = "k" })

local function getElementState(frame)
    if not elementState[frame] then
        elementState[frame] = {}
    end
    return elementState[frame]
end

-- OPT-18: Style generation counter for dirty-flag caching.
-- Bumped before every full-pass ForEachVisibleEntry call so that subsequent
-- per-entry InitEntry calls with matching classToken can skip redundant work.
DMX._dmStyleGeneration = 0

-- OPT-27: Cache GetAllSessionWindows result to avoid per-call table allocation.
-- Invalidated on DM reset and full restyle (ApplyDamageMeterStyling).
local cachedSessionWindows = nil
local cachedSessionWindowsValid = false

-- Overlay visibility management for UIParent-parented overlays.
-- UIParent-parented overlays don't auto-hide when entries are hidden/recycled
-- by the ScrollBox. Use a per-window "hide then show visible" pattern.
local windowOverlays = setmetatable({}, { __mode = "k" })

-- Strong set of session windows styled this session (for cleanup iteration)
-- windowOverlays/windowState are weak-key tables and can't be reliably iterated.
local knownSessionWindows = {}

DMX._windowState = windowState
DMX._elementState = elementState
DMX._windowOverlays = windowOverlays
DMX._knownSessionWindows = knownSessionWindows
DMX._getWindowState = getWindowState
DMX._getElementState = getElementState

--------------------------------------------------------------------------------
-- Overlay Registry & Visibility Management
--------------------------------------------------------------------------------

local function registerDMOverlay(sessionWindow, overlay)
    if not sessionWindow or not overlay then return end
    if not windowOverlays[sessionWindow] then
        windowOverlays[sessionWindow] = {}
    end
    windowOverlays[sessionWindow][#windowOverlays[sessionWindow] + 1] = overlay
end

local function hideWindowOverlays(sessionWindow)
    local overlays = sessionWindow and windowOverlays[sessionWindow]
    if not overlays then return end
    for _, overlay in ipairs(overlays) do
        overlay:Hide()
    end
end

local function hideAllDMOverlays()
    -- Restore Blizzard entry visuals before hiding overlays
    for _, overlays in pairs(windowOverlays) do
        for _, overlay in ipairs(overlays) do
            if overlay._lastEntry then
                -- Late-binding: DMX._RestoreBlizzardEntryContent set by overlays.lua
                DMX._RestoreBlizzardEntryContent(overlay._lastEntry)
            end
            overlay:Hide()
        end
    end
    -- Clip frames, button overlays, title right-click overlays, export buttons from windowState
    for sessionWindow in pairs(knownSessionWindows) do
        local ws = windowState[sessionWindow]
        if ws then
            if ws.clipFrame then ws.clipFrame:Hide() end
            if ws.buttonOverlays then
                if ws.buttonOverlays.typeArrow then ws.buttonOverlays.typeArrow:Hide() end
                if ws.buttonOverlays.settingsIcon then ws.buttonOverlays.settingsIcon:Hide() end
            end
            if ws.titleRightClickOverlay then ws.titleRightClickOverlay:Hide() end
            if ws.exportButton then ws.exportButton:Hide() end
            if ws.exportMenu then ws.exportMenu:Hide() end
        end
    end
end

DMX._registerDMOverlay = registerDMOverlay
DMX._hideWindowOverlays = hideWindowOverlays
DMX._hideAllDMOverlays = hideAllDMOverlays

--------------------------------------------------------------------------------
-- Slash command handlers (/dmshow, /dmreset)
--------------------------------------------------------------------------------

function DMX._SlashToggleShow()
    local profile = addon.db and addon.db.profile
    if not profile then return end

    -- Read current state from profile setting (or fall back to CVar)
    local s = profile.damageMeterSettings
    local currentlyEnabled
    if s and s.enableDamageMeter ~= nil then
        currentlyEnabled = s.enableDamageMeter
    else
        local v = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("damageMeterEnabled")
        currentlyEnabled = (v == "1")
    end

    local newState = not currentlyEnabled

    -- Store in profile (consistent with the UI toggle)
    if not profile.damageMeterSettings then profile.damageMeterSettings = {} end
    profile.damageMeterSettings.enableDamageMeter = newState

    -- Set CVar (defer if in combat)
    local value = newState and "1" or "0"
    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "damageMeterEnabled", value)
        end
    end

    if InCombatLockdown() then
        -- Keyed: toggling again in the same fight replaces the queued closure,
        -- so the last toggle's CVar value is the one that lands on regen. The
        -- captured value is safe for the same reason.
        addon.Events.RunOutOfCombat(function()
            applyCVar()
            if newState and addon.ApplyStyles then
                C_Timer.After(0, function() addon:ApplyStyles() end)
            end
        end, "DMX:cvarToggle")
        addon:Print(newState and "Damage Meter will show after combat." or "Damage Meter will hide after combat.")
    else
        applyCVar()
        if newState then
            C_Timer.After(0, function()
                if addon.ApplyStyles then addon:ApplyStyles() end
            end)
            addon:Print("Damage Meter shown.")
        else
            hideAllDMOverlays()
            addon:Print("Damage Meter hidden.")
        end
    end
end

function DMX._SlashReset()
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        C_DamageMeter.ResetAllCombatSessions()
        addon:Print("Damage Meter data reset.")
    end
end

--------------------------------------------------------------------------------
-- Zone Snapshot (for export data)
--------------------------------------------------------------------------------

local function GetCurrentZoneLabel()
    local instName, instType, _, diffName = GetInstanceInfo()
    if instName and instName ~= "" and instType ~= "none" then
        return (diffName and diffName ~= "") and (instName .. " (" .. diffName .. ")") or instName
    else
        return (instName and instName ~= "") and instName or "Open World"
    end
end

DMX._dmResetZoneSnapshot = nil

local function SnapshotResetZone()
    DMX._dmResetZoneSnapshot = GetCurrentZoneLabel()
end

DMX._GetCurrentZoneLabel = GetCurrentZoneLabel

--------------------------------------------------------------------------------
-- Session Window Discovery
--------------------------------------------------------------------------------

-- OPT-27: Invalidate the session window cache so the next call rebuilds it.
local function InvalidateSessionWindowCache()
    cachedSessionWindows = nil
    cachedSessionWindowsValid = false
end

local function GetAllSessionWindows()
    if cachedSessionWindowsValid and cachedSessionWindows then
        return cachedSessionWindows
    end

    local windows = {}

    -- Try numbered session windows (DamageMeterSessionWindow1, DamageMeterSessionWindow2, etc.)
    for i = 1, 10 do
        local windowName = "DamageMeterSessionWindow" .. i
        local window = _G[windowName]
        if window then
            table.insert(windows, window)
        end
    end

    -- Also check DamageMeter.sessionWindows array if it exists
    local dmFrame = _G.DamageMeter
    if dmFrame and dmFrame.sessionWindows then
        for _, window in ipairs(dmFrame.sessionWindows) do
            -- Avoid duplicates
            local found = false
            for _, existing in ipairs(windows) do
                if existing == window then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(windows, window)
            end
        end
    end

    cachedSessionWindows = windows
    cachedSessionWindowsValid = true
    return windows
end

-- Iterate all visible entries in a session window's ScrollBox
local function ForEachVisibleEntry(sessionWindow, callback)
    if not sessionWindow then return end

    local scrollBox = sessionWindow.ScrollBox
    if not scrollBox then return end

    -- Method 1: ForEachFrame (standard ScrollBox API)
    if scrollBox.ForEachFrame then
        local ok, err = pcall(scrollBox.ForEachFrame, scrollBox, callback)
        if not ok and addon._debugDM then
            addon._debugDMLog = addon._debugDMLog or {}
            addon._debugDMLog[#addon._debugDMLog + 1] = "ForEachFrame error: " .. tostring(err)
        end
        return
    end

    -- Method 2: GetFrames (alternative API)
    if scrollBox.GetFrames then
        local ok, frames = pcall(scrollBox.GetFrames, scrollBox)
        if ok and frames then
            for _, frame in ipairs(frames) do
                pcall(callback, frame)
            end
        elseif not ok and addon._debugDM then
            addon._debugDMLog = addon._debugDMLog or {}
            addon._debugDMLog[#addon._debugDMLog + 1] = "GetFrames error: " .. tostring(frames)
        end
        return
    end

    -- Method 3: Iterate ScrollTarget children directly
    local scrollTarget = scrollBox.ScrollTarget
    if scrollTarget and scrollTarget.GetChildren then
        local children = { scrollTarget:GetChildren() }
        for _, child in ipairs(children) do
            if child and child.StatusBar then
                pcall(callback, child)
            end
        end
    elseif addon._debugDM then
        addon._debugDMLog = addon._debugDMLog or {}
        addon._debugDMLog[#addon._debugDMLog + 1] = "No iteration method found on ScrollBox"
    end
end

-- Get scroll signature for scroll change detection
local function GetScrollSignature()
    local windows = GetAllSessionWindows()
    for _, sessionWindow in ipairs(windows) do
        local sig = nil
        ForEachVisibleEntry(sessionWindow, function(entryFrame)
            if not sig then
                local nt = entryFrame.nameText
                if issecretvalue(nt) then nt = nil end
                if not nt then
                    nt = entryFrame.sourceName
                    if issecretvalue(nt) then nt = nil end
                end
                local style = entryFrame.style
                if issecretvalue(style) then style = nil end
                sig = (nt or "") .. "|" .. tostring(style or "")
            end
        end)
        if sig then return sig end
    end
    return ""
end

DMX._InvalidateSessionWindowCache = InvalidateSessionWindowCache
DMX._GetAllSessionWindows = GetAllSessionWindows
DMX._ForEachVisibleEntry = ForEachVisibleEntry
DMX._GetScrollSignature = GetScrollSignature

--------------------------------------------------------------------------------
-- State-Based Opacity (Out-of-Combat Fade)
--------------------------------------------------------------------------------

-- Window alpha for the current state (core/opacity.lua): the Edit Mode value
-- (50-100) in combat, the addon slider (0-100) out of it.
local DM_OPACITY_OPTS = { combatMin = 50 }

local function GetDamageMeterOpacityAlpha(db)
    local alpha = addon.Opacity.Resolve(db, addon.Opacity.Keys.CombatOnly, DM_OPACITY_OPTS)
    return alpha
end

local function RefreshDamageMeterOpacity(comp)
    if not comp or not comp.db then return end
    local db = comp.db
    local alpha = GetDamageMeterOpacityAlpha(db)
    local windows = GetAllSessionWindows()
    for _, sessionWindow in ipairs(windows) do
        SafeSetAlpha(sessionWindow, alpha)
        -- UIParent-parented Scoot overlays don't inherit session window alpha
        local ws = windowState[sessionWindow]
        if ws then
            if ws.clipFrame then SafeSetAlpha(ws.clipFrame, alpha) end
            if ws.titleRightClickOverlay then SafeSetAlpha(ws.titleRightClickOverlay, alpha) end
            if ws.exportButton then SafeSetAlpha(ws.exportButton, alpha) end
        end
        -- LocalPlayerEntry overlay (UIParent-parented, doesn't inherit session window alpha)
        local lpe = sessionWindow.LocalPlayerEntry
        if lpe then
            local lpeElSt = elementState[lpe]
            if lpeElSt and lpeElSt.entryOverlay then
                SafeSetAlpha(lpeElSt.entryOverlay, alpha)
            end
        end
    end
end

DMX._RefreshDamageMeterOpacity = RefreshDamageMeterOpacity

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    -- Gate: only register if X sub-toggle is enabled (DB key: "damageMeter")
    if not self:IsModuleEnabled("damageMeter", "damageMeter") then return end

    local Component = addon.ComponentPrototype

    local damageMeter = Component:New({
        id = "damageMeter",
        name = "Damage Meters X",
        frameName = "DamageMeter",
        settings = {
            -- Edit Mode-managed settings (11 total)
            -- Style dropdown: Default(0), Bordered(1), Thin(2)
            style = { type = "editmode", settingId = nil, default = 0, ui = { hidden = true } },
            -- Layout settings
            frameWidth = { type = "editmode", settingId = nil, default = 300, ui = { hidden = true } },
            frameHeight = { type = "editmode", settingId = nil, default = 200, ui = { hidden = true } },
            barHeight = { type = "editmode", settingId = nil, default = 20, ui = { hidden = true } },
            padding = { type = "editmode", settingId = nil, default = 4, ui = { hidden = true } },
            -- Transparency/Opacity settings
            opacity = { type = "editmode", settingId = nil, default = 100, ui = { hidden = true } },
            background = { type = "editmode", settingId = nil, default = 80, ui = { hidden = true } },
            -- Text size
            textSize = { type = "editmode", settingId = nil, default = 100, ui = { hidden = true } },
            -- Visibility dropdown: Always(0), InCombat(1), Hidden(2)
            visibility = { type = "editmode", settingId = nil, default = 0, ui = { hidden = true } },
            -- Checkboxes
            showSpecIcon = { type = "editmode", settingId = nil, default = true, ui = { hidden = true } },
            showClassColor = { type = "editmode", settingId = nil, default = true, ui = { hidden = true } },

            -- Addon-only settings (bar styling)
            barTexture = { type = "addon", default = "default", ui = { hidden = true } },
            -- Foreground color: mode ("default", "class", "custom") + tint for custom
            barForegroundColorMode = { type = "addon", default = "default", ui = { hidden = true } },
            barForegroundTint = { type = "addon", default = { r = 1, g = 0.8, b = 0, a = 1 }, ui = { hidden = true } },
            -- Background color: mode ("default", "custom") + tint for custom
            barBackgroundColorMode = { type = "addon", default = "default", ui = { hidden = true } },
            barBackgroundTint = { type = "addon", default = { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }, ui = { hidden = true } },
            -- Legacy settings (kept for backwards compatibility)
            barForegroundColor = { type = "addon", default = { 1, 0.8, 0, 1 }, ui = { hidden = true } },
            barBackgroundColor = { type = "addon", default = { 0.1, 0.1, 0.1, 0.8 }, ui = { hidden = true } },

            -- Bar border settings
            barBorderStyle = { type = "addon", default = "default", ui = { hidden = true } },
            barBorderTintEnabled = { type = "addon", default = false, ui = { hidden = true } },
            barBorderTintColor = { type = "addon", default = { 1, 1, 1, 1 }, ui = { hidden = true } },
            barBorderThickness = { type = "addon", default = 1, ui = { hidden = true } },
            barBorderHiddenEdges = { type = "addon", default = {}, ui = { hidden = true } },

            -- Icon settings (matching Essential Cooldowns Border pattern)
            iconBorderEnable = { type = "addon", default = false, ui = { hidden = true } },
            iconBorderTintEnable = { type = "addon", default = false, ui = { hidden = true } },
            iconBorderTintColor = { type = "addon", default = { r = 1, g = 1, b = 1, a = 1 }, ui = { hidden = true } },
            iconBorderThickness = { type = "addon", default = 1, ui = { hidden = true } },
            iconBorderInsetH = { type = "addon", default = 0, ui = { hidden = true } },  -- Horizontal (left/right)
            iconBorderInsetV = { type = "addon", default = 2, ui = { hidden = true } },  -- Vertical (top/bottom) - default 2 for clipped icons

            -- JiberishIcons integration (class icons to replace spec icons)
            jiberishIconsEnabled = { type = "addon", default = false, ui = { hidden = true } },
            jiberishIconsStyle = { type = "addon", default = "fabled", ui = { hidden = true } },

            -- Text settings - Title (header/dropdown)
            -- Default color is Blizzard's GameFontNormalMed1 gold: r=1.0, g=0.82, b=0
            textTitle = { type = "addon", default = {
                fontFace = "FRIZQT__",
                fontStyle = "OUTLINE",
                scaleMultiplier = 1.0,
                colorMode = "default",
                color = { 1.0, 0.82, 0, 1 },
            }, ui = { hidden = true }},

            -- Text settings - Timer (session timer [00:05:23])
            -- Same defaults as textTitle (both inherit GameFontNormalMed1)
            textTimer = { type = "addon", default = {
                fontFace = "FRIZQT__",
                fontStyle = "OUTLINE",
                colorMode = "default",
                color = { 1.0, 0.82, 0, 1 },
            }, ui = { hidden = true }},

            -- Button tint (header dropdown arrows, settings icon, session name text)
            buttonTintMode = { type = "addon", default = "default", ui = { hidden = true }},
            buttonTint = { type = "addon", default = { r = 1, g = 0.82, b = 0, a = 1 }, ui = { hidden = true }},

            -- Button icon overlays (custom atlas-based icons for uniform styling)
            buttonIconOverlaysEnabled = { type = "addon", default = false, ui = { hidden = true }},

            -- Header backdrop settings
            headerBackdropShow = { type = "addon", default = true, ui = { hidden = true }},
            headerBackdropTint = { type = "addon", default = { r = 1, g = 1, b = 1, a = 1 }, ui = { hidden = true }},

            -- Enhanced title: show session type alongside meter type (e.g., "DPS (Current)")
            showSessionInTitle = { type = "addon", default = false, ui = { hidden = true }},

            -- Right-click title text to open meter type dropdown
            titleTextRightClickMeterType = { type = "addon", default = false, ui = { hidden = true }},

            -- Text settings - Names (player names on bars)
            textNames = { type = "addon", default = {
                fontFace = "FRIZQT__",
                fontStyle = "OUTLINE",
                fontSize = 12,
                color = { 1, 1, 1, 1 },
                colorMode = "default",
                scaleMultiplier = 1.0,
            }, ui = { hidden = true }},

            -- Text settings - Numbers (DPS/HPS values)
            textNumbers = { type = "addon", default = {
                fontFace = "FRIZQT__",
                fontStyle = "OUTLINE",
                fontSize = 12,
                color = { 1, 1, 1, 1 },
                colorMode = "default",
                scaleMultiplier = 1.0,
            }, ui = { hidden = true }},

            -- Window border settings
            windowShowBorder = { type = "addon", default = false, ui = { hidden = true } },
            windowBorderStyle = { type = "addon", default = "default", ui = { hidden = true } },
            windowBorderColor = { type = "addon", default = { 1, 1, 1, 1 }, ui = { hidden = true } },
            windowBorderThickness = { type = "addon", default = 1, ui = { hidden = true } },

            -- Window background settings
            windowCustomBackdrop = { type = "addon", default = false, ui = { hidden = true } },
            windowBackdropTexture = { type = "addon", default = "default", ui = { hidden = true } },
            windowBackdropColor = { type = "addon", default = { 0.1, 0.1, 0.1, 0.9 }, ui = { hidden = true } },

            -- Export settings
            exportEnabled = { type = "addon", default = false, ui = { hidden = true } },
            exportButtonXOffset = { type = "addon", default = 0, ui = { hidden = true } },
            exportChatChannel = { type = "addon", default = "PARTY", ui = { hidden = true } },
            exportChatLineCount = { type = "addon", default = 5, ui = { hidden = true } },
            highScoreFont = { type = "addon", default = "PRESS_START_2P", ui = { hidden = true } },

            -- Out-of-combat opacity (state-based fade)
            opacityOutOfCombat = { type = "addon", default = 100, ui = { hidden = true } },

            -- Quality of Life settings
            autoResetData = { type = "addon", default = "off", ui = { hidden = true } },
            autoResetPrompt = { type = "addon", default = true, ui = { hidden = true } },
            enableSlashDM = { type = "addon", default = false, ui = { hidden = true } },
        },
        ApplyStyling = function(self) DMX._ApplyDamageMeterStyling(self) end,
        RefreshOpacity = function(self) RefreshDamageMeterOpacity(self) end,
    })

    self:RegisterComponent(damageMeter)

    -- Start the shared passive inspect service for export spec/ilvl data
    if addon.Inspect then
        addon.Inspect:EnsureStarted()
    end

    -- Zone snapshot: track where data started
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        hooksecurefunc(C_DamageMeter, "ResetAllCombatSessions", SnapshotResetZone)
    end
    SnapshotResetZone()

    -- Re-snapshot after PLAYER_ENTERING_WORLD so GetInstanceInfo() has difficulty info
    addon.Events.OnWorldEntered(function()
        SnapshotResetZone()
    end)

    -- Event-driven restyling (replaces Rule 11-violating hooksecurefunc on system frames)
    -- DamageMeter inherits EditModeDamageMeterSystemTemplate — hooks on its tree cause taint.
    -- These events fire when Blizzard refreshes the meter, matching the old hook triggers.
    local dmEventPending = false
    local dmResetPending = false
    local function onDamageMeterEvent(_, event)
        local comp = addon.Components and addon.Components["damageMeter"]
        if not comp or not comp.db then return end
        if addon.IsComponentUnconfigured(comp) then return end
        if event == "DAMAGE_METER_RESET" then
            InvalidateSessionWindowCache()
            dmResetPending = true
        end
        if dmEventPending then return end
        dmEventPending = true
        C_Timer.After(0, function()
            dmEventPending = nil
            if dmResetPending then
                dmResetPending = false
                hideAllDMOverlays()
            end
            local dmFrame = _G.DamageMeter
            if not dmFrame or not dmFrame:IsShown() then
                hideAllDMOverlays()
                return
            end
            if PlayerInCombat() then
                -- Combat: data-only update (bar fill + text, no style changes)
                DMX._UpdateAllOverlayData(comp)
            else
                if comp and comp.ApplyStyling then
                    comp:ApplyStyling()
                end
            end
        end)
    end
    for _, event in ipairs({
        "DAMAGE_METER_COMBAT_SESSION_UPDATED",
        "DAMAGE_METER_RESET",
        "DAMAGE_METER_CURRENT_SESSION_UPDATED",
        "PLAYER_REGEN_ENABLED",
    }) do
        damageMeter:On(event, onDamageMeterEvent)
    end

    -- Overlay sync ticker: keeps overlays current with ScrollBox state.
    -- Runs every 0.1s using RefreshVisibleOverlays (lightweight, OPT-18 cached)
    -- instead of the previous signature-based change detection which missed intermediate
    -- scroll states and left overlays stale for up to 300ms.
    local dmWasShown = false
    local lastKnownWindowCount = 0  -- track session window count for new-window detection
    local scrollTicker = CreateFrame("Frame")
    scrollTicker:SetScript("OnUpdate", function(self, elapsed)
        self._elapsed = (self._elapsed or 0) + elapsed
        if self._elapsed < 0.1 then return end
        self._elapsed = 0
        local dmFrame = _G.DamageMeter
        local isShown = dmFrame and dmFrame:IsShown()
        if not isShown then
            if dmWasShown then
                dmWasShown = false
                hideAllDMOverlays()
            end
            return
        end
        if not dmWasShown then
            dmWasShown = true
            -- Sync window count to avoid double-trigger on initial show
            local sw = dmFrame.sessionWindows
            lastKnownWindowCount = sw and #sw or 0
            -- Frame just became visible — trigger full restyle
            local comp = addon.Components and addon.Components["damageMeter"]
            if comp and comp.ApplyStyling and not PlayerInCombat() then
                if not addon.IsComponentUnconfigured(comp) then
                    comp:ApplyStyling()
                end
            end
            return
        end
        -- Detect new session windows created by user (not covered by any Blizzard event)
        local sw = dmFrame.sessionWindows
        local currentWindowCount = sw and #sw or 0
        if currentWindowCount ~= lastKnownWindowCount then
            lastKnownWindowCount = currentWindowCount
            InvalidateSessionWindowCache()
            local comp = addon.Components and addon.Components["damageMeter"]
            if comp and comp.ApplyStyling and not PlayerInCombat() then
                if not addon.IsComponentUnconfigured(comp) then
                    comp:ApplyStyling()
                end
            end
            return
        end
        local comp = addon.Components and addon.Components["damageMeter"]
        if not comp or not comp.db then return end
        if addon.IsComponentUnconfigured(comp) then return end
        if PlayerInCombat() then
            DMX._UpdateAllOverlayData(comp)
        else
            DMX._RefreshVisibleOverlays(comp)
        end
    end)

    -- Auto-reset data event handler
    damageMeter:On("PLAYER_ENTERING_WORLD", function(_, _, isInitialLogin, isReloadingUi)
        if isInitialLogin or isReloadingUi then return end

        local comp = addon.Components and addon.Components["damageMeter"]
        if not comp or not comp.db then return end
        if addon.IsComponentUnconfigured(comp) then return end
        local mode = comp.db.autoResetData
        if mode ~= "instance" then return end

        local inInstance, instanceType = IsInInstance()
        if not inInstance then return end
        if instanceType ~= "party" and instanceType ~= "raid" and instanceType ~= "scenario" then return end

        if not C_DamageMeter or not C_DamageMeter.ResetAllCombatSessions then return end

        if comp.db.autoResetPrompt then
            if addon.Dialogs and addon.Dialogs.Show then
                addon.Dialogs:Show("SCOOT_DM_RESET_CONFIRM", {
                    onAccept = function()
                        C_DamageMeter.ResetAllCombatSessions()
                    end,
                })
            end
        else
            C_DamageMeter.ResetAllCombatSessions()
        end
    end)

    -- Debug: /scoot debug dm frames — overlay diagnostic info in copyable window
    addon.DebugDMFrames = function()
        local lines = {}
        local function push(s) lines[#lines + 1] = s end

        local windows = GetAllSessionWindows()
        push("Session windows found: " .. #windows)
        push("")
        for i, sw in ipairs(windows) do
            local ws = windowState[sw]
            local clipFrame = ws and ws.clipFrame
            local overlayCount = windowOverlays[sw] and #windowOverlays[sw] or 0
            push(string.format("Window %d: overlays=%d, clipFrame=%s", i, overlayCount, tostring(clipFrame ~= nil)))
            if clipFrame then
                local ok, cl = pcall(clipFrame.GetFrameLevel, clipFrame)
                local ok2, cs = pcall(clipFrame.GetFrameStrata, clipFrame)
                push(string.format("  ClipFrame: level=%s, strata=%s", ok and tostring(cl) or "?", ok2 and tostring(cs) or "?"))
            end
            local entryCount = 0
            ForEachVisibleEntry(sw, function(entry)
                entryCount = entryCount + 1
                local ok, el = pcall(entry.GetFrameLevel, entry)
                local ok2, es = pcall(entry.GetFrameStrata, entry)
                local elSt = elementState[entry]
                local ov = elSt and elSt.entryOverlay
                local ovLevel, ovStrata = "none", "none"
                if ov then
                    local ok3, ol = pcall(ov.GetFrameLevel, ov)
                    local ok4, os = pcall(ov.GetFrameStrata, ov)
                    ovLevel = ok3 and tostring(ol) or "?"
                    ovStrata = ok4 and tostring(os) or "?"
                end
                push(string.format("  Entry %d: level=%s strata=%s | Overlay: level=%s strata=%s shown=%s",
                    entryCount,
                    ok and tostring(el) or "?", ok2 and tostring(es) or "?",
                    ovLevel, ovStrata,
                    ov and tostring(ov:IsShown()) or "no overlay"))
            end)
            push(string.format("  Visible entries: %d", entryCount))
            push("")
        end

        -- Include buffered error log if debug tracing was on
        if addon._debugDMLog and #addon._debugDMLog > 0 then
            push("--- Debug Log (" .. #addon._debugDMLog .. " entries) ---")
            for _, msg in ipairs(addon._debugDMLog) do
                push(msg)
            end
        end

        if addon.DebugShowWindow then
            addon.DebugShowWindow("DM Frame Diagnostics", lines)
        end
    end

    -- Toggle DM debug mode
    addon.SetDMDebug = function(enabled)
        addon._debugDM = enabled
        if addon.Print then
            addon:Print("DM debug " .. (enabled and "enabled" or "disabled"))
        end
    end

    -- Debug: /scoot debug dm state — zero-touch diagnostic dump (copyable window)
    addon.DebugDMState = function()
        local lines = {}
        local function push(s) lines[#lines + 1] = s end

        local profile = addon.db and addon.db.profile
        if not profile then
            push("[DM State] No profile loaded")
            if addon.DebugShowWindow then addon.DebugShowWindow("DM Zero-Touch State", lines) end
            return
        end

        push("=== Component DB State ===")

        -- Check rawget for components table
        local components = rawget(profile, "components")
        push("rawget(profile, 'components') = " .. (components and "TABLE" or "nil"))

        -- Check rawget for damageMeter within components
        local dmTbl = components and rawget(components, "damageMeter") or nil
        push("rawget(components, 'damageMeter') = " .. (dmTbl and "TABLE" or "nil"))

        -- Dump DM table contents
        if dmTbl and type(dmTbl) == "table" then
            local count = 0
            for key, value in pairs(dmTbl) do
                count = count + 1
                local vStr
                if type(value) == "table" then
                    local n = 0
                    for _ in pairs(value) do n = n + 1 end
                    vStr = "table(" .. n .. " keys)"
                else
                    vStr = tostring(value)
                end
                push("  " .. tostring(key) .. " = " .. vStr .. " [" .. type(value) .. "]")
            end
            push("  Total keys: " .. count)
        end

        push("")
        push("=== Proxy State ===")

        -- Check component proxy state
        local comp = addon.Components and addon.Components["damageMeter"]
        if not comp then
            push("Component not registered!")
            if addon.DebugShowWindow then addon.DebugShowWindow("DM Zero-Touch State", lines) end
            return
        end
        push("comp._ScootDBProxy = " .. (comp._ScootDBProxy and "exists" or "nil"))
        push("comp.db == proxy? " .. tostring(comp.db == comp._ScootDBProxy))
        push("comp.db type = " .. type(comp.db))
        local mt = getmetatable(comp.db)
        push("comp.db has metatable? " .. (mt and "yes" or "no"))

        push("")
        push("=== Overlay Count ===")

        -- Count overlays
        local totalOverlays = 0
        local shownOverlays = 0
        for _, overlays in pairs(windowOverlays) do
            for _, ov in ipairs(overlays) do
                totalOverlays = totalOverlays + 1
                if ov:IsShown() then shownOverlays = shownOverlays + 1 end
            end
        end
        push("Overlays: " .. shownOverlays .. " shown / " .. totalOverlays .. " total")

        push("")
        push("=== Captured Stacks ===")

        -- EnsureComponentDB materialization stack (buffered by base/core.lua)
        if DMX._dmMaterializeStack then
            push("EnsureComponentDB materialized damageMeter:")
            push(DMX._dmMaterializeStack)
        else
            push("EnsureComponentDB: NOT called for damageMeter this session")
        end

        push("")

        -- ApplyDamageMeterStyling first-call stack (buffered by styling.lua)
        if DMX._dmApplyTraced and DMX._dmApplyStack then
            push("ApplyDamageMeterStyling first call:")
            push(DMX._dmApplyStack)
        else
            push("ApplyDamageMeterStyling: NOT called this session")
        end

        if addon.DebugShowWindow then
            addon.DebugShowWindow("DM Zero-Touch State", lines)
        end
    end
end, "damageMeter")

local Commands = addon.Commands

addon:RegisterDebugCommand({
    name = "dm", help = "Native damage meter",
    verbs = {
        { word = "state", help = "zero-touch diagnostic", fn = function()
            if addon.DebugDMState then addon.DebugDMState() else Commands.NotAvailable("Damage Meter") end
        end },
        { word = "export", usage = "export [overall|current|expired]", help = "session export", fn = function(session) addon.DebugExportDamageMeters(session) end },
        { word = "frames", help = "window and overlay frames", fn = function()
            if addon.DebugDMFrames then addon.DebugDMFrames() else Commands.NotAvailable("Damage Meter") end
        end },
        { word = "trace", usage = "trace <on|off>", help = "buffer the error log into the frames dump", fn = function(token)
            token = string.lower(token or "")
            if token ~= "on" and token ~= "off" then return Commands.USAGE end
            if addon.SetDMDebug then addon.SetDMDebug(token == "on") else Commands.NotAvailable("Damage Meter") end
        end },
    },
})
