-- damagemetersY/core.lua - Damage Meters Y namespace, component registration, DB structure
local addonName, addon = ...

--------------------------------------------------------------------------------
-- Damage Meters Y — Namespace, Component Registration, DB Structure
--------------------------------------------------------------------------------

addon.DamageMetersY = {}
local DMY = addon.DamageMetersY

DMY.MAX_WINDOWS = 5
DMY.MAX_COLUMNS = 5
DMY.MAX_POOL = 25

--------------------------------------------------------------------------------
-- Meter types and session types
--------------------------------------------------------------------------------

-- Read off the client's enums by name, never as a literal. The 12.x numbers
-- stand in only where an enum table is absent altogether. A name the client's
-- enum lacks stays nil here: a column format that needs it is not built
-- (columns.lua) and a comparison against it is false.
local function enumByName(enum, numbers)
    if type(enum) ~= "table" then return numbers end
    local out = {}
    for name in pairs(numbers) do
        out[name] = enum[name]
    end
    return out
end

DMY.MT = enumByName(Enum and Enum.DamageMeterType, {
    DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5,
    Dispels = 6, DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10,
})
DMY.ST = enumByName(Enum and Enum.DamageMeterSessionType, { Overall = 0, Current = 1, Expired = 2 })

-- A set of meter types from their names, skipping any the client lacks.
function DMY.MeterTypeSet(...)
    local set = {}
    for i = 1, select("#", ...) do
        local mt = DMY.MT[(select(i, ...))]
        if mt ~= nil then set[mt] = true end
    end
    return set
end

-- Runtime state (not persisted)
DMY._windows = {}       -- [1..5] = { frame, barRows, localPlayerRow, ... }
DMY._comp = nil          -- Component reference (set during registration)
DMY._initialized = false
DMY._inCombat = false
DMY._combatStartTime = 0
DMY._preCombatDuration = 0 -- duration before current combat started

--------------------------------------------------------------------------------
-- Host
--------------------------------------------------------------------------------

-- Two addons list these files. What differs between them is one optional
-- table, addon.MetersHost, read at the moment of use: where the per-window
-- config and the positions are stored, what the meter is called, and how
-- Blizzard's meter comes back when this one is switched off. With no table
-- set every reader falls back to the profile keys and the plain words below.
local function Host()
    local host = addon.MetersHost
    if type(host) == "table" then return host end
    return nil
end
DMY._Host = Host

-- The meter's name in a line a player reads.
function DMY.DisplayName()
    local host = Host()
    return (host and host.name) or "Damage Meter"
end

-- One window's name in Edit Mode.
function DMY.WindowLabel(windowIndex)
    local host = Host()
    return ((host and host.windowLabel) or "Damage Meter") .. " " .. windowIndex
end

-- The face a text setting falls to when it stores none.
function DMY.FallbackFont()
    local host = Host()
    return (host and host.fallbackFont) or "ROBOTO_SEMICOND_BOLD"
end

-- Debug trace buffer
DMY._traceLog = {}
DMY._traceEnabled = false -- enable with the debug command: dmY trace on

function DMY._Trace(msg)
    if not DMY._traceEnabled then return end
    local ts = string.format("%.1f", GetTime() % 1000)
    table.insert(DMY._traceLog, ts .. " " .. msg)
    -- Cap at 200 entries
    if #DMY._traceLog > 200 then
        table.remove(DMY._traceLog, 1)
    end
end

function addon.DebugDMYTrace()
    if #DMY._traceLog == 0 then
        addon.DebugShowWindow("DMY Trace", "No trace entries. Fight something first.")
        return
    end
    addon.DebugShowWindow("DMY Trace", DMY._traceLog)
end

--------------------------------------------------------------------------------
-- Per-Window DB
--------------------------------------------------------------------------------

-- What a window record is created with. columnShare is the part of the
-- window's width one undragged value column takes (layout.lua,
-- DMY._GetNameFraction); the name column gets what the columns leave.
local WINDOW_DEFAULTS = {
    [1] = { enabled = true,  sessionType = DMY.ST.Current, columns = { { format = "dps" } }, frameWidth = 250, frameHeight = 250, windowScale = 1.0, columnShare = 0.2 },
    [2] = { enabled = false, sessionType = DMY.ST.Current, columns = { { format = "dps" } }, frameWidth = 250, frameHeight = 250, windowScale = 1.0, columnShare = 0.2 },
    [3] = { enabled = false, sessionType = DMY.ST.Current, columns = { { format = "dps" } }, frameWidth = 250, frameHeight = 250, windowScale = 1.0, columnShare = 0.2 },
    [4] = { enabled = false, sessionType = DMY.ST.Current, columns = { { format = "dps" } }, frameWidth = 250, frameHeight = 250, windowScale = 1.0, columnShare = 0.2 },
    [5] = { enabled = false, sessionType = DMY.ST.Current, columns = { { format = "dps" } }, frameWidth = 250, frameHeight = 250, windowScale = 1.0, columnShare = 0.2 },
}
table.freeze(WINDOW_DEFAULTS)

-- The sizes a record stored before it carried its own takes: the values every
-- window had then. A record made today is written whole from WINDOW_DEFAULTS.
local LEGACY_SIZING = { frameWidth = 350, frameHeight = 250, windowScale = 1.0 }

-- What a reader gets while this meter's gate is closed: defaults that are
-- never stored. The settings search draws every page to index it, this
-- meter's included, and a page drawn with the meter off must leave no window
-- configs behind in the profile.
local scratchWindows = {}

-- The five window configs: the host's table when a host answers, else the
-- profile's. Either is edited in place by every caller of _GetWindowConfig.
local function WindowsTable()
    if not addon:IsModuleEnabled("damageMeter", "damageMeterV2") then
        return scratchWindows
    end
    local host = Host()
    if host and host.GetWindows then
        return host.GetWindows()
    end
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    if not profile.damageMeterV2Windows then
        profile.damageMeterV2Windows = {}
    end
    return profile.damageMeterV2Windows
end

function DMY._EnsureWindowsDB()
    local wins = WindowsTable()
    if type(wins) ~= "table" then return nil end
    for i = 1, DMY.MAX_WINDOWS do
        if not wins[i] then
            local def = WINDOW_DEFAULTS[i]
            wins[i] = {
                enabled = def.enabled,
                sessionType = def.sessionType,
                columns = {},
                frameWidth = def.frameWidth,
                frameHeight = def.frameHeight,
                windowScale = def.windowScale,
                columnShare = def.columnShare,
            }
            for j, col in ipairs(def.columns) do
                wins[i].columns[j] = { format = col.format }
            end
        end
        if not wins[i].columns or #wins[i].columns == 0 then
            wins[i].columns = { { format = "dps" } }
        end
        -- An older record without its own sizing keeps the size it drew at.
        if not wins[i].frameWidth then wins[i].frameWidth = LEGACY_SIZING.frameWidth end
        if not wins[i].frameHeight then wins[i].frameHeight = LEGACY_SIZING.frameHeight end
        if not wins[i].windowScale then wins[i].windowScale = LEGACY_SIZING.windowScale end
    end
    return wins
end

function DMY._GetWindowConfig(windowIndex)
    local wins = DMY._EnsureWindowsDB()
    return wins and wins[windowIndex]
end

-- Writes the five window records again from WINDOW_DEFAULTS. The table is
-- emptied in place, since a host may store it by reference. Window positions
-- are stored elsewhere and stay. False while the meter's gate is closed.
function DMY.RecreateWindowRecords()
    if not addon:IsModuleEnabled("damageMeter", "damageMeterV2") then return false end
    local wins = WindowsTable()
    if type(wins) ~= "table" then return false end
    for i = 1, DMY.MAX_WINDOWS do
        wins[i] = nil
    end
    DMY._EnsureWindowsDB()
    if DMY._comp then DMY._ApplyStyling(DMY._comp) end
    return true
end

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    -- The initializer runs whenever the damage meter module is on, whichever
    -- meter is the active one, so the slash words and the export's zone
    -- record start here, ahead of this meter's own gate.
    DMY._InstallSlashWords()
    DMY._StartZoneRecord()

    -- Gate: only register if Y sub-toggle is enabled (DB key: "damageMeterV2")
    if not self:IsModuleEnabled("damageMeter", "damageMeterV2") then return end

    -- When Y is active, ensure X sub-toggle is disabled.
    -- Handles the case where moduleEnabled.damageMeter is still a boolean
    -- (existing profiles before sub-toggles were added).
    if self.SetModuleEnabled then
        self:SetModuleEnabled("damageMeter", "damageMeter", false)
    end

    -- Pre-materialize the component's table so the zero-touch proxy never
    -- stands in for it and ApplyStyling is not skipped. A host store
    -- (addon.ComponentStore) installs no proxy and takes no table here.
    if not addon.ComponentStore then
        local components = addon.ComponentsUtil.GetContainerFor(nil, true)
        if type(components) == "table" and type(rawget(components, "damageMeterV2")) ~= "table" then
            components["damageMeterV2"] = {}
        end
    end

    local Component = addon.ComponentPrototype
    local host = Host()

    local comp = Component:New({
        id = "damageMeterV2",
        name = (host and host.name) or "Damage Meters Y",
        settings = {
            -- Layout
            windowScale     = { type = "addon", default = 1.0 },
            frameWidth      = { type = "addon", default = 350 },
            frameHeight     = { type = "addon", default = 250 },
            barHeight       = { type = "addon", default = 22 },
            barSpacing      = { type = "addon", default = 2 },

            -- Bars
            barTexture              = { type = "addon", default = "default" },
            barForegroundColorMode  = { type = "addon", default = "class" },
            barCustomColor          = { type = "addon", default = { 0.8, 0.7, 0.2, 1 } },
            barBackgroundColor      = { type = "addon", default = { 0.1, 0.1, 0.1, 0.8 } },
            barBorderStyle          = { type = "addon", default = "none" },
            barBorderColorMode      = { type = "addon", default = "default" },
            barBorderColor          = { type = "addon", default = { 0, 0, 0, 1 } },
            barBorderThickness      = { type = "addon", default = 1 },
            barBorderInsetH         = { type = "addon", default = 0 },
            barBorderInsetV         = { type = "addon", default = 0 },
            -- "default" is the full-height bar. Thin is the start: the bar runs
            -- under the name, and names and bars are both class color.
            barMode                 = { type = "addon", default = "thin" },
            hideRankNumbers         = { type = "addon", default = false },
            barBgTexture            = { type = "addon", default = "default" },
            barBgColorMode          = { type = "addon", default = "default" },
            barBgCustomColor        = { type = "addon", default = { 0.1, 0.1, 0.1, 0.8 } },
            barBackgroundOpacity    = { type = "addon", default = 80 },

            -- Icons
            showIcons           = { type = "addon", default = true },
            iconStyle           = { type = "addon", default = "default" }, -- "default" or JI style key
            jiberishIconsEnabled = { type = "addon", default = false },

            -- Text: Names
            textNames = { type = "addon", default = {
                fontFace = "ROBOTO_SEMICOND_BOLD", fontStyle = "OUTLINE", fontSize = 12,
                colorMode = "class", color = { 1, 1, 1, 1 },
            }},
            hideRealmNames = { type = "addon", default = true },
            -- Text: Values
            textValues = { type = "addon", default = {
                fontFace = "ROBOTO_SEMICOND_BLACK", fontStyle = "SHADOWTHICKOUTLINE", fontSize = 11,
                colorMode = "default", color = { 1, 1, 1, 1 },
            }},
            -- Text: Title
            textTitle = { type = "addon", default = {
                fontFace = "ROBOTO_SEMICOND_BLACK", fontStyle = "SHADOWTHICKOUTLINE", fontSize = 13,
                colorMode = "default", color = { 1, 1, 1, 1 },
            }},
            -- Text: Timer
            textTimer = { type = "addon", default = {
                fontFace = "ROBOTO_SEMICOND_BOLD", fontStyle = "OUTLINE", fontSize = 13,
                colorMode = "default", color = { 1.0, 0.82, 0, 1 },
            }},
            -- Vertical title mode
            verticalTitleMode = { type = "addon", default = false },
            -- Text: Column Headers
            textHeaders = { type = "addon", default = {
                fontFace = "ROBOTO_SEMICOND_BLACK", fontStyle = "SHADOWTHICKOUTLINE", fontSize = 10,
                colorMode = "default", color = { 0.8, 0.8, 0.8, 1 },
            }},
            -- Column header display: "regular" | "abbreviated" | "icons"
            columnHeaderMode = { type = "addon", default = "regular" },

            -- Window
            showBackdrop            = { type = "addon", default = true },
            windowBackdropColor     = { type = "addon", default = { 0.06, 0.06, 0.08, 0.95 } },
            windowBackdropOpacity   = { type = "addon", default = 95 },
            -- "solid" (windowBackdropColor) or a "window" key of DMY.PanelArt (art.lua)
            windowBackdropTexture   = { type = "addon", default = "solid" },
            windowBorderStyle       = { type = "addon", default = "none" },
            windowBorderColor       = { type = "addon", default = { 0, 0, 0, 1 } },
            windowBorderThickness   = { type = "addon", default = 1 },

            -- Visibility / Opacity
            opacity             = { type = "addon", default = 100 },
            opacityOutOfCombat  = { type = "addon", default = 100 },
            visibility          = { type = "addon", default = "always" },
            showLocalPlayer     = { type = "addon", default = true },

            -- QoL
            updateThrottle  = { type = "addon", default = 1.0 },
            autoResetData   = { type = "addon", default = "off" },
            autoResetPrompt = { type = "addon", default = true },
            enableSlashDM   = { type = "addon", default = false },

            -- Export
            exportEnabled       = { type = "addon", default = false },
            exportChatChannel   = { type = "addon", default = "PARTY" },
            exportChatLineCount = { type = "addon", default = 5 },

            -- Title
            titleMode           = { type = "addon", default = "auto" },
            customTitle         = { type = "addon", default = "" },
            showTitleBarBackdrop = { type = "addon", default = true },
            -- "solid" (DMY.TITLE_BAR_COLOR) or a "title" key of DMY.PanelArt (art.lua)
            titleBarBackdropTexture = { type = "addon", default = "solid" },
            titleBarBackdropOpacity = { type = "addon", default = 90 },
        },

        ApplyStyling = function(self)
            DMY._ApplyStyling(self)
        end,

        RefreshOpacity = function(self)
            DMY._RefreshOpacity(self)
        end,
    })

    self:RegisterComponent(comp)
    DMY._comp = comp

    -- Start the shared passive inspect service that populates ilvl/spec
    -- caches for export. Idempotent; X is disabled whenever Y is active,
    -- so Y owns the call here.
    if addon.Inspect then
        addon.Inspect:EnsureStarted()
    end

    -- Bootstrap Y on first PLAYER_ENTERING_WORLD.
    -- The component system's ApplyStyling gate may skip it (proxy/zero-touch),
    -- so it self-bootstraps after DB linking is complete.
    addon.Events.OnWorldEntered(function()
        if comp.db then
            DMY._ApplyStyling(comp)
        end
    end)
end, "damageMeter")

--------------------------------------------------------------------------------
-- Blizzard's meter
--------------------------------------------------------------------------------

-- While this meter is on, every styling pass turns Blizzard's off by CVar. One
-- host puts the CVar back through its profile reconciler. A host with none
-- hands over two accessors: the write that takes Blizzard's meter from on to
-- off is recorded, and at world entry with this meter's gate closed the record
-- is honoured and cleared. A meter the player already had off stays off.
local function BlizzardMeterRecord()
    local host = Host()
    if host and host.GetHidBlizzardMeter and host.SetHidBlizzardMeter then
        return host
    end
    return nil
end

local function NoteBlizzardMeterHidden()
    local host = BlizzardMeterRecord()
    if not host or host.GetHidBlizzardMeter() then return end
    if not (C_CVar and C_CVar.GetCVar) then return end
    local ok, value = pcall(C_CVar.GetCVar, "damageMeterEnabled")
    if ok and value == "1" then
        host.SetHidBlizzardMeter(true)
    end
end

local function RestoreBlizzardMeter()
    local host = BlizzardMeterRecord()
    if not host or not host.GetHidBlizzardMeter() then return end
    if addon:IsModuleEnabled("damageMeter", "damageMeterV2") then return end
    if not (C_CVar and C_CVar.SetCVar) then return end
    addon.Events.RunOutOfCombat(function()
        -- Kept off addon.ApplyDamageMeterEnabled: the restore for a host with no profile CVar reconciler.
        pcall(C_CVar.SetCVar, "damageMeterEnabled", "1")
        host.SetHidBlizzardMeter(false)
    end, "DamageMetersY:restoreBlizzardMeter")
end

addon.Events.OnWorldEntered(RestoreBlizzardMeter)

--------------------------------------------------------------------------------
-- ApplyStyling / RefreshOpacity
--------------------------------------------------------------------------------

function DMY._ApplyStyling(comp)
    -- Guard: bail if Y is not enabled on the current profile (handles profile switches)
    if not addon:IsModuleEnabled("damageMeter", "damageMeterV2") then
        if DMY._initialized then
            for i = 1, DMY.MAX_WINDOWS do
                local win = DMY._windows[i]
                if win and win.frame then
                    win.frame:Hide()
                end
            end
        end
        return
    end

    -- Initialize frames on first styling pass
    if not DMY._initialized then
        DMY._Initialize(comp)
    end

    -- Disable Blizzard meter via CVar when Y is active.
    -- Kept off addon.ApplyDamageMeterEnabled: styling-pass re-assert while the Y meter owns the frame; not a profile toggle.
    if C_CVar and C_CVar.SetCVar and not InCombatLockdown() then
        NoteBlizzardMeterHidden()
        pcall(C_CVar.SetCVar, "damageMeterEnabled", "0")
    end

    -- Show/hide and style each window
    for i = 1, DMY.MAX_WINDOWS do
        DMY._UpdateVisibility(i, comp)
        local win = DMY._windows[i]
        if win and win.frame:IsShown() then
            DMY._ApplyFullStyling(i, comp)
            DMY._UpdateSessionHeader(i, comp)
        end
    end

    -- Trigger a full data refresh
    if not DMY._inCombat then
        DMY._FullRefreshAllWindows()
    end

    -- Refresh opacity
    DMY._RefreshOpacity(comp)
end

-- Window alpha for the current state (core/opacity.lua): the Edit Mode value
-- (50-100) in combat, the addon slider (0-100) out of it.
local OPACITY_OPTS = { combatMin = 50 }

-- Nothing tells a FontString that an ancestor's alpha moved, so the Deep
-- Shadow copies re-read it after every write (core/fontpair.lua copyAlphaFor).
local function WriteWindowAlpha(win, alpha)
    win.frame:SetAlpha(alpha)
    if addon.FontPair then addon.FontPair.RefreshInheritedAlpha() end
end

-- Through the state fade (core/opacity.lua): where the transition engine is
-- loaded a combat edge fades, each tick through the window's own writer, and
-- elsewhere the call answers the resolved alpha and this is the plain write.
function DMY._RefreshOpacity(comp)
    if not DMY._initialized then return end
    local alpha, state = addon.Opacity.Resolve(comp.db, addon.Opacity.Keys.CombatOnly, OPACITY_OPTS)
    for i = 1, DMY.MAX_WINDOWS do
        local win = DMY._windows[i]
        if win and win.frame:IsShown() then
            if not win.opacityTick then
                win.opacityTick = function(value) WriteWindowAlpha(win, value) end
            end
            WriteWindowAlpha(win, addon.Opacity.Fade(win.frame, alpha, state, win.opacityTick))
        end
    end

    -- Update visibility for combat-based modes
    for i = 1, DMY.MAX_WINDOWS do
        DMY._UpdateVisibility(i, comp)
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function DMY._Initialize(comp)
    if DMY._initialized then return end
    DMY._initialized = true

    DMY._EnsureWindowsDB()

    -- Migrate the retired Hide Bars toggle into its Bar Mode equivalent
    if comp.db then
        if comp.db.showBars == false then
            comp.db.barMode = "hidden"
        end
        comp.db.showBars = nil
    end

    -- Create all window frames
    for i = 1, DMY.MAX_WINDOWS do
        DMY._CreateWindow(i, comp)
    end

    -- Build the abbreviation config eagerly so DMY._abbrevError is
    -- inspectable right after login (the debug command: dmY abbrev)
    DMY._RebuildAbbrevConfig()

    -- Initialize event handling
    DMY._InitializeEvents(comp)

    -- Initialize Edit Mode positioning
    DMY._InitializeEditMode()
end

--------------------------------------------------------------------------------
-- Session Labels
--------------------------------------------------------------------------------

local SESSION_LABELS = {}
if DMY.ST.Overall ~= nil then SESSION_LABELS[DMY.ST.Overall] = "Overall" end
if DMY.ST.Current ~= nil then SESSION_LABELS[DMY.ST.Current] = "Current" end
table.freeze(SESSION_LABELS)

function DMY._GetSessionLabel(sessionType, sessionID, sessionName)
    if sessionID then
        return sessionName or ("Combat #" .. sessionID)
    end
    return SESSION_LABELS[sessionType] or "Unknown"
end

--------------------------------------------------------------------------------
-- Copy Window Settings
--------------------------------------------------------------------------------

function DMY.CopyWindowSettings(sourceIdx, destIdx)
    if type(sourceIdx) ~= "number" or type(destIdx) ~= "number" then return end
    if sourceIdx == destIdx then return end
    if sourceIdx < 1 or sourceIdx > DMY.MAX_WINDOWS then return end
    if destIdx < 1 or destIdx > DMY.MAX_WINDOWS then return end

    local wins = DMY._EnsureWindowsDB()
    if not wins then return end
    local src, dst = wins[sourceIdx], wins[destIdx]
    if not src or not dst then return end

    local function deepcopy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, vv in pairs(v) do out[k] = deepcopy(vv) end
        return out
    end

    dst.columns     = deepcopy(src.columns)
    dst.nameWidthFraction = src.nameWidthFraction
    dst.columnShare = src.columnShare
    dst.frameWidth  = src.frameWidth
    dst.frameHeight = src.frameHeight
    dst.windowScale = src.windowScale

    if DMY._comp then DMY._ApplyStyling(DMY._comp) end
end

--------------------------------------------------------------------------------
-- Window Sizing
--------------------------------------------------------------------------------

-- Single write path for per-window sizing, shared by the settings panel
-- sliders and the Edit Mode mirror so the two surfaces cannot drift.
local SIZING_BOUNDS = {
    windowScale = { min = 0.5, max = 2.0 },
    frameWidth  = { min = 100, max = 800 },
    frameHeight = { min = 100, max = 600 },
}

function DMY.SetWindowSizing(windowIndex, key, value)
    local bounds = SIZING_BOUNDS[key]
    if not bounds then return end
    local cfg = DMY._GetWindowConfig(windowIndex)
    if not cfg then return end
    value = tonumber(value)
    if not value then return end
    cfg[key] = math.max(bounds.min, math.min(bounds.max, value))
    if DMY._comp then DMY._ApplyStyling(DMY._comp) end
end
