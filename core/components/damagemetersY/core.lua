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

-- Runtime state (not persisted)
DMY._windows = {}       -- [1..5] = { frame, barRows, localPlayerRow, ... }
DMY._comp = nil          -- Component reference (set during registration)
DMY._initialized = false
DMY._inCombat = false
DMY._combatStartTime = 0
DMY._preCombatDuration = 0 -- duration before current combat started

-- Debug trace buffer
DMY._traceLog = {}
DMY._traceEnabled = false -- enable with /scoot debug dmY trace on

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

local WINDOW_DEFAULTS = {
    [1] = { enabled = true,  sessionType = 0, columns = { { format = "dps" } }, frameWidth = 350, frameHeight = 250, windowScale = 1.0 },
    [2] = { enabled = false, sessionType = 1, columns = { { format = "dps" } }, frameWidth = 350, frameHeight = 250, windowScale = 1.0 },
    [3] = { enabled = false, sessionType = 1, columns = { { format = "dps" } }, frameWidth = 350, frameHeight = 250, windowScale = 1.0 },
    [4] = { enabled = false, sessionType = 1, columns = { { format = "dps" } }, frameWidth = 350, frameHeight = 250, windowScale = 1.0 },
    [5] = { enabled = false, sessionType = 1, columns = { { format = "dps" } }, frameWidth = 350, frameHeight = 250, windowScale = 1.0 },
}
table.freeze(WINDOW_DEFAULTS)

function DMY._EnsureWindowsDB()
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    if not profile.damageMeterV2Windows then
        profile.damageMeterV2Windows = {}
    end
    local wins = profile.damageMeterV2Windows
    for i = 1, DMY.MAX_WINDOWS do
        if not wins[i] then
            local def = WINDOW_DEFAULTS[i]
            wins[i] = {
                enabled = def.enabled,
                sessionType = def.sessionType,
                columns = {},
            }
            for j, col in ipairs(def.columns) do
                wins[i].columns[j] = { format = col.format }
            end
        end
        if not wins[i].columns or #wins[i].columns == 0 then
            wins[i].columns = { { format = "dps" } }
        end
        -- Ensure per-window sizing fields exist
        if not wins[i].frameWidth then wins[i].frameWidth = WINDOW_DEFAULTS[i].frameWidth end
        if not wins[i].frameHeight then wins[i].frameHeight = WINDOW_DEFAULTS[i].frameHeight end
        if not wins[i].windowScale then wins[i].windowScale = WINDOW_DEFAULTS[i].windowScale end
    end
    return wins
end

function DMY._GetWindowConfig(windowIndex)
    local wins = DMY._EnsureWindowsDB()
    return wins and wins[windowIndex]
end

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    -- Gate: only register if Y sub-toggle is enabled (DB key: "damageMeterV2")
    if not self:IsModuleEnabled("damageMeter", "damageMeterV2") then return end

    -- When Y is active, ensure X sub-toggle is disabled.
    -- Handles the case where moduleEnabled.damageMeter is still a boolean
    -- (existing profiles before sub-toggles were added).
    if self.SetModuleEnabled then
        self:SetModuleEnabled("damageMeter", "damageMeter", false)
    end

    -- Pre-materialize component DB so the proxy system doesn't skip ApplyStyling.
    if self.db and self.db.profile then
        if not self.db.profile.components then
            self.db.profile.components = {}
        end
        if not self.db.profile.components["damageMeterV2"] then
            self.db.profile.components["damageMeterV2"] = {}
        end
    end

    local Component = addon.ComponentPrototype

    local comp = Component:New({
        id = "damageMeterV2",
        name = "Damage Meters Y",
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
            barMode                 = { type = "addon", default = "default" },
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

function DMY._RefreshOpacity(comp)
    if not DMY._initialized then return end
    local alpha = addon.Opacity.Resolve(comp.db, addon.Opacity.Keys.CombatOnly, OPACITY_OPTS)
    for i = 1, DMY.MAX_WINDOWS do
        local win = DMY._windows[i]
        if win and win.frame:IsShown() then
            win.frame:SetAlpha(alpha)
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
    -- inspectable right after login (/scoot debug dmY abbrev)
    DMY._RebuildAbbrevConfig()

    -- Initialize event handling
    DMY._InitializeEvents(comp)

    -- Initialize Edit Mode positioning
    DMY._InitializeEditMode()
end

--------------------------------------------------------------------------------
-- Session Labels
--------------------------------------------------------------------------------

local SESSION_LABELS = {
    [0] = "Overall",
    [1] = "Current",
}
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
