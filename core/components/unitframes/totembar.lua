-- totembar.lua - Totem Bar styling for Player Unit Frame
-- Styles icon borders and timer text on totem buttons for supported classes
local addonName, addon = ...

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

local hookedBorders = setmetatable({}, { __mode = "k" })
local hookedDurations = setmetatable({}, { __mode = "k" })
local eventFrame = nil

--------------------------------------------------------------------------------
-- Debug Helper
--------------------------------------------------------------------------------

local DEBUG_TOTEM_BAR = false
local function debugPrint(...)
    if DEBUG_TOTEM_BAR and addon and addon.DebugPrint then
        addon.DebugPrint("[TotemBar]", ...)
    elseif DEBUG_TOTEM_BAR then
        print("[Scoot TotemBar]", ...)
    end
end

--------------------------------------------------------------------------------
-- Configuration Access
--------------------------------------------------------------------------------

local function ensureConfig()
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end

    db.unitFrames = db.unitFrames or {}
    db.unitFrames.Player = db.unitFrames.Player or {}
    db.unitFrames.Player.totemBar = db.unitFrames.Player.totemBar or {}

    local cfg = db.unitFrames.Player.totemBar

    -- Ensure sub-tables exist
    cfg.iconBorders = cfg.iconBorders or {}
    cfg.timerText = cfg.timerText or {}

    return cfg
end

local function getIconBordersConfig()
    local cfg = ensureConfig()
    return cfg and cfg.iconBorders or {}
end

local function getTimerTextConfig()
    local cfg = ensureConfig()
    return cfg and cfg.timerText or {}
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

local function applyBorderStyling(border, hidden)
    if not border then return end

    if hidden then
        pcall(border.SetAlpha, border, 0)
        debugPrint("Border hidden via SetAlpha(0)")

        -- Hook to maintain hidden state when Blizzard shows the border
        if not hookedBorders[border] then
            hookedBorders[border] = true
            hooksecurefunc(border, "Show", function(self)
                local cfg = getIconBordersConfig()
                if cfg.hidden then
                    C_Timer.After(0, function()
                        pcall(self.SetAlpha, self, 0)
                    end)
                end
            end)
            hooksecurefunc(border, "SetAlpha", function(self, alpha)
                local cfg = getIconBordersConfig()
                if cfg.hidden and alpha ~= 0 then
                    C_Timer.After(0, function()
                        pcall(self.SetAlpha, self, 0)
                    end)
                end
            end)
            debugPrint("Installed border hooks")
        end
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
        debugPrint("Timer text hidden via SetAlpha(0)")

        -- Hook to maintain hidden state
        if not hookedDurations[duration] then
            hookedDurations[duration] = true
            hooksecurefunc(duration, "Show", function(self)
                local tcfg = getTimerTextConfig()
                if tcfg.hidden then
                    C_Timer.After(0, function()
                        pcall(self.SetAlpha, self, 0)
                    end)
                end
            end)
            hooksecurefunc(duration, "SetAlpha", function(self, alpha)
                local tcfg = getTimerTextConfig()
                if tcfg.hidden and alpha ~= 0 then
                    C_Timer.After(0, function()
                        pcall(self.SetAlpha, self, 0)
                    end)
                end
            end)
            debugPrint("Installed duration hooks for hidden state")
        end
        return
    end

    -- Show the duration text
    pcall(duration.SetAlpha, duration, 1)

    -- Apply font settings
    local fontFace = cfg.fontFace or "FRIZQT__"
    local face = addon.ResolveFontFace and addon.ResolveFontFace(fontFace) or "Fonts\\FRIZQT__.TTF"
    local size = tonumber(cfg.size) or 12
    local style = cfg.style or "OUTLINE"

    -- Normalize style
    if style == "NONE" then
        style = ""
    end

    pcall(duration.SetFont, duration, face, size, style)
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

    -- Hook to reapply styling when Blizzard updates the duration
    if not hookedDurations[duration] then
        hookedDurations[duration] = true
        -- Hook SetText to reapply styling after Blizzard updates
        hooksecurefunc(duration, "SetText", function(self, text)
            local tcfg = getTimerTextConfig()
            if tcfg.hidden then
                C_Timer.After(0, function()
                    pcall(self.SetAlpha, self, 0)
                end)
            else
                -- Reapply font and color (text updates might reset them)
                C_Timer.After(0, function()
                    local ff = tcfg.fontFace or "FRIZQT__"
                    local f = addon.ResolveFontFace and addon.ResolveFontFace(ff) or "Fonts\\FRIZQT__.TTF"
                    local s = tonumber(tcfg.size) or 12
                    local st = tcfg.style or "OUTLINE"
                    if st == "NONE" then st = "" end
                    pcall(self.SetFont, self, f, s, st)
                    local col = tcfg.color or { 1, 1, 1, 1 }
                    pcall(self.SetTextColor, self, col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1)
                end)
            end
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

    local cfg = ensureConfig()
    if not cfg then
        debugPrint("No config available, skipping")
        return
    end

    local borderCfg = cfg.iconBorders or {}
    local textCfg = cfg.timerText or {}

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

    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    eventFrame:SetScript("OnEvent", function(self, event, ...)
        -- Defer to allow Blizzard to finish its updates
        C_Timer.After(0.1, function()
            addon.ApplyTotemBarStyling()
        end)
    end)

    debugPrint("Event watcher registered")
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

-- Hook into addon initialization
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    -- Defer initialization to ensure all systems are ready
    C_Timer.After(0.5, function()
        setupEventWatcher()
        addon.ApplyTotemBarStyling()
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)
