-- totembar.lua - Totem Bar styling for Player Unit Frame
-- Styles icon borders and timer text on totem buttons for supported classes
local addonName, addon = ...

-- Font-half opts for the totem duration text
local totemFontOpts = { size = 12 }

--------------------------------------------------------------------------------
-- Supported Classes
--------------------------------------------------------------------------------
-- TotemFrame displays temporary summons via GetTotemInfo() API.
-- Despite the name, it's not just for Shamans:
--   SHAMAN: All totems (Fire, Earth, Water, Air)
--   DEATHKNIGHT: Ghoul (when temporary), Abomination Limb
--   DRUID: Grove Guardians, Wild Mushroom (Efflorescence)
--   MONK: Jade Serpent Statue, Black Ox Statue

local TOTEM_BAR_CLASSES = {
    SHAMAN = true,
    DEATHKNIGHT = true,
    DRUID = true,
    MONK = true,
}

--------------------------------------------------------------------------------
-- State Tracking
--------------------------------------------------------------------------------

local styledDurations = setmetatable({}, { __mode = "k" })
local eventFrame = nil

--------------------------------------------------------------------------------
-- Debug Helper
--------------------------------------------------------------------------------

local DEBUG_TOTEM_BAR = false
local function debugPrint(...)
    if DEBUG_TOTEM_BAR then
        addon.DebugPrint("[TotemBar]", ...)
    end
end

--------------------------------------------------------------------------------
-- Configuration Access
--------------------------------------------------------------------------------

local function getTotemBarConfig()
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    local unitFrames = rawget(db, "unitFrames")
    local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
    return playerCfg and rawget(playerCfg, "totemBar") or nil
end

local function getIconBordersConfig()
    local cfg = getTotemBarConfig()
    return cfg and rawget(cfg, "iconBorders") or nil
end

local function getTimerTextConfig()
    local cfg = getTotemBarConfig()
    return cfg and rawget(cfg, "timerText") or nil
end

--------------------------------------------------------------------------------
-- Class Eligibility
--------------------------------------------------------------------------------

function addon.UnitFrames_TotemBar_ShouldShow()
    local classToken = UnitClassBase and UnitClassBase("player") or select(2, UnitClass("player"))
    return TOTEM_BAR_CLASSES[classToken] == true
end

--------------------------------------------------------------------------------
-- Iterate Totem Buttons
--------------------------------------------------------------------------------
-- TotemFrame uses pooled buttons with dynamic IDs.
-- Each button has .Border (Texture) and .Duration (FontString) children.

local function iterateTotemButtons(callback)
    local tf = _G.TotemFrame
    if not tf then
        debugPrint("TotemFrame not found")
        return
    end

    local children = { tf:GetChildren() }
    for _, child in ipairs(children) do
        -- Totem buttons have Border and Duration children
        local border = child.Border
        local duration = child.Duration
        if border and duration then
            callback(child, border, duration)
        end
    end
end

--------------------------------------------------------------------------------
-- Apply Icon Border Styling
--------------------------------------------------------------------------------

-- Hide-enforcement (core/enforce.lua): the keys read the configuration live
-- and every re-assert runs after a stack break, as before.
local Enforce = addon.Enforce
local HIDE_METHODS = { "Show", "SetAlpha" }
local BORDER_HIDE_OPTS = {
    methods = HIDE_METHODS,
    timing = "defer",
    when = function()
        local cfg = getIconBordersConfig()
        return cfg ~= nil and not not cfg.hidden
    end,
}
local TIMER_HIDE_OPTS = {
    methods = HIDE_METHODS,
    timing = "defer",
    when = function()
        local cfg = getTimerTextConfig()
        return cfg ~= nil and not not cfg.hidden
    end,
}

local function applyBorderStyling(border, hidden)
    if not border then return end

    if hidden then
        pcall(border.SetAlpha, border, 0)
        Enforce.Install(border, "totemBorder", BORDER_HIDE_OPTS)
        debugPrint("Border hidden via SetAlpha(0)")
    else
        pcall(border.SetAlpha, border, 1)
        debugPrint("Border shown via SetAlpha(1)")
    end
end

--------------------------------------------------------------------------------
-- Apply Timer Text Styling (Baseline 6)
--------------------------------------------------------------------------------

local function applyTimerTextStyling(duration, cfg)
    if not duration then return end

    -- Handle hidden state
    if cfg.hidden then
        pcall(duration.SetAlpha, duration, 0)
        Enforce.Install(duration, "totemTimer", TIMER_HIDE_OPTS)
        debugPrint("Timer text hidden via SetAlpha(0)")
        return
    end

    -- Show the duration text
    pcall(duration.SetAlpha, duration, 1)

    -- Apply font settings (ApplyFontStyle decodes the pseudo-style, shadow
    -- half included, and normalizes NONE itself)
    local face, size, style = addon.ResolveTextFont(cfg, totemFontOpts)
    addon.ApplyFontStyle(duration, face, size, style)
    debugPrint("Set font:", face, size, style)

    -- Apply color
    local c = cfg.color or { 1, 1, 1, 1 }
    pcall(duration.SetTextColor, duration, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    debugPrint("Set color:", c[1], c[2], c[3], c[4])

    -- Apply offset via point adjustment
    local offsetX = cfg.offset and cfg.offset.x or 0
    local offsetY = cfg.offset and cfg.offset.y or 0
    if offsetX ~= 0 or offsetY ~= 0 then
        -- Duration is typically anchored to BOTTOM of the button
        -- Adjusted using ClearAllPoints + SetPoint
        local parent = duration:GetParent()
        if parent then
            pcall(function()
                duration:ClearAllPoints()
                duration:SetPoint("BOTTOM", parent, "BOTTOM", offsetX, offsetY)
            end)
            debugPrint("Set offset:", offsetX, offsetY)
        end
    end

    -- Reapply font and color after Blizzard updates the text. The hidden case
    -- belongs to the Show and SetAlpha keys above; this hook closes over the
    -- duration and never reads its arguments.
    if not styledDurations[duration] then
        styledDurations[duration] = true
        hooksecurefunc(duration, "SetText", function()
            local tcfg = getTimerTextConfig()
            if not tcfg or tcfg.hidden then return end
            C_Timer.After(0, function()
                addon.ApplyTextFont(duration, tcfg, totemFontOpts)
                local col = tcfg.color or { 1, 1, 1, 1 }
                pcall(duration.SetTextColor, duration, col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1)
            end)
        end)
        debugPrint("Installed duration SetText hook")
    end
end

--------------------------------------------------------------------------------
-- Main Apply Function
--------------------------------------------------------------------------------

function addon.ApplyTotemBarStyling()
    -- Skip if class doesn't use totem bar
    if not addon.UnitFrames_TotemBar_ShouldShow() then
        debugPrint("Class does not use TotemFrame, skipping")
        return
    end

    local cfg = getTotemBarConfig()
    if not cfg then
        debugPrint("No config available, skipping")
        return
    end

    local borderCfg = rawget(cfg, "iconBorders") or {}
    local textCfg = rawget(cfg, "timerText") or {}

    debugPrint("Applying totem bar styling...")

    iterateTotemButtons(function(button, border, duration)
        debugPrint("Processing button:", button:GetName() or "unnamed")

        -- Apply border styling
        applyBorderStyling(border, borderCfg.hidden)

        -- Apply timer text styling
        applyTimerTextStyling(duration, textCfg)
    end)

    debugPrint("Totem bar styling applied")
end

--------------------------------------------------------------------------------
-- Event Registration
--------------------------------------------------------------------------------

local function setupEventWatcher()
    if eventFrame then return end

    -- Skip if class doesn't use totem bar
    if not addon.UnitFrames_TotemBar_ShouldShow() then
        return
    end

    local function onEvent()
        -- Defer to allow Blizzard to finish its updates
        C_Timer.After(0.1, function()
            addon.ApplyTotemBarStyling()
        end)
    end
    eventFrame = {
        addon.Events.On("UnitFrames:TotemBar", "PLAYER_TOTEM_UPDATE", onEvent),
        addon.Events.On("UnitFrames:TotemBar", "PLAYER_ENTERING_WORLD", onEvent),
    }

    debugPrint("Event watcher registered")
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

-- Hook into addon initialization
addon.Events.Once("UnitFrames:TotemBar", "PLAYER_LOGIN", function()
    -- Defer initialization to ensure all systems are ready
    C_Timer.After(0.5, function()
        setupEventWatcher()
        addon.ApplyTotemBarStyling()
    end)
end)
