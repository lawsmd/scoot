-- Theme.lua - Foundation for UI settings panel
-- Provides: Theme system, accent color management, font helpers
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Theme = {}
local Theme = addon.UI.Theme

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Default Matrix green: #00FF41 (classic terminal green)
Theme.DEFAULT_ACCENT = { r = 0, g = 1, b = 0.255, a = 1 }

-- Background colors (semi-transparent for layered effect with noise overlay)
Theme.BACKGROUND = { r = 0.004, g = 0.004, b = 0.006, a = 0.96 }
Theme.BACKGROUND_SOLID = { r = 0.004, g = 0.004, b = 0.006, a = 0.99 }

-- Text colors
Theme.TEXT_PRIMARY = { r = 1, g = 1, b = 1, a = 1 }
Theme.TEXT_DIM = { r = 0.6, g = 0.6, b = 0.6, a = 1 }
Theme.TEXT_DIM_LIGHT = { r = 0.75, g = 0.75, b = 0.75, a = 1 }  -- Lighter for use on gray backgrounds

-- Collapsible section background (subtle gray for visual distinction)
Theme.COLLAPSIBLE_BG = { r = 0.12, g = 0.12, b = 0.14, a = 1 }

-- Border settings (glow disabled until proper texture assets are created)
Theme.BORDER_WIDTH = 3  -- Slightly thicker for visibility
Theme.GLOW_ALPHA = 0.35  -- Reserved for future use
Theme.GLOW_WIDTH = 6     -- Reserved for future use

--------------------------------------------------------------------------------
-- Font Registration (JetBrains Mono)
--------------------------------------------------------------------------------

local FONT_BASE = "Interface\\AddOns\\Scoot\\media\\fonts\\"

-- Register JetBrains Mono in addon.Fonts alongside existing fonts
-- NOTE: Font files must be bundled in media/fonts/
addon.Fonts = addon.Fonts or {}
addon.Fonts.JETBRAINS_REG = FONT_BASE .. "JetBrainsMono-Regular.ttf"
addon.Fonts.JETBRAINS_MED = FONT_BASE .. "JetBrainsMono-Medium.ttf"
addon.Fonts.JETBRAINS_BOLD = FONT_BASE .. "JetBrainsMono-Bold.ttf"

-- UI font references
Theme.Fonts = {
    LABEL = addon.Fonts.JETBRAINS_MED,
    VALUE = addon.Fonts.JETBRAINS_REG,
    HEADER = addon.Fonts.JETBRAINS_BOLD,
    BUTTON = addon.Fonts.JETBRAINS_MED,
    -- Fallback to Roboto if JetBrains not available
    PROPORTIONAL = addon.Fonts.ROBOTO_REG or FONT_BASE .. "Roboto-Regular.ttf",
}

--------------------------------------------------------------------------------
-- Texture paths
--------------------------------------------------------------------------------

Theme.Textures = {
    NOISE_OVERLAY = "Interface\\AddOns\\Scoot\\media\\textures\\noise-overlay",
}

--------------------------------------------------------------------------------
-- Pub/Sub System for Accent Color Changes
--------------------------------------------------------------------------------

Theme._subscribers = {}

function Theme:Subscribe(key, callback)
    if type(key) ~= "string" or type(callback) ~= "function" then return end
    self._subscribers[key] = callback
end

function Theme:Unsubscribe(key)
    self._subscribers[key] = nil
end

function Theme:NotifySubscribers()
    local r, g, b, a = self:GetAccentColor()
    for key, callback in pairs(self._subscribers) do
        local ok, err = pcall(callback, r, g, b, a)
        if not ok then
            -- Silently log; don't break other subscribers
            if addon.Debug then
                addon.Debug("UI Theme subscriber error", key, err)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Accent Color Accessors
--------------------------------------------------------------------------------

function Theme:GetAccentColor()
    local db = addon.db and addon.db.global
    if db and db.accentColor then
        local c = db.accentColor
        return c.r or self.DEFAULT_ACCENT.r,
               c.g or self.DEFAULT_ACCENT.g,
               c.b or self.DEFAULT_ACCENT.b,
               c.a or 1
    end
    return self.DEFAULT_ACCENT.r, self.DEFAULT_ACCENT.g, self.DEFAULT_ACCENT.b, 1
end

function Theme:SetAccentColor(r, g, b, a)
    if not addon.db or not addon.db.global then
        return false
    end
    addon.db.global.accentColor = {
        r = r or self.DEFAULT_ACCENT.r,
        g = g or self.DEFAULT_ACCENT.g,
        b = b or self.DEFAULT_ACCENT.b,
        a = a or 1
    }
    self:NotifySubscribers()
    return true
end

function Theme:ResetAccentColor()
    return self:SetAccentColor(
        self.DEFAULT_ACCENT.r,
        self.DEFAULT_ACCENT.g,
        self.DEFAULT_ACCENT.b,
        self.DEFAULT_ACCENT.a
    )
end

--------------------------------------------------------------------------------
-- Derived Color Helpers
--------------------------------------------------------------------------------

function Theme:GetGlowColor()
    local r, g, b = self:GetAccentColor()
    return r, g, b, self.GLOW_ALPHA
end

function Theme:GetBorderColor()
    local r, g, b = self:GetAccentColor()
    return r, g, b, 1
end

function Theme:GetBackgroundColor()
    return self.BACKGROUND.r, self.BACKGROUND.g, self.BACKGROUND.b, self.BACKGROUND.a
end

function Theme:GetBackgroundSolidColor()
    return self.BACKGROUND_SOLID.r, self.BACKGROUND_SOLID.g, self.BACKGROUND_SOLID.b, self.BACKGROUND_SOLID.a
end

function Theme:GetPrimaryTextColor()
    return self.TEXT_PRIMARY.r, self.TEXT_PRIMARY.g, self.TEXT_PRIMARY.b, self.TEXT_PRIMARY.a
end

function Theme:GetDimTextColor()
    return self.TEXT_DIM.r, self.TEXT_DIM.g, self.TEXT_DIM.b, self.TEXT_DIM.a
end

function Theme:GetDimTextLightColor()
    return self.TEXT_DIM_LIGHT.r, self.TEXT_DIM_LIGHT.g, self.TEXT_DIM_LIGHT.b, self.TEXT_DIM_LIGHT.a
end

function Theme:GetCollapsibleBgColor()
    return self.COLLAPSIBLE_BG.r, self.COLLAPSIBLE_BG.g, self.COLLAPSIBLE_BG.b, self.COLLAPSIBLE_BG.a
end

--------------------------------------------------------------------------------
-- Font Helper Functions
--------------------------------------------------------------------------------

-- Check if a font file exists/is loadable
local function FontExists(path)
    if not path then return false end
    -- Create a temporary font object to test
    local testFont = CreateFont("ScootFontTest_" .. math.random(100000))
    local ok = pcall(testFont.SetFont, testFont, path, 12, "")
    return ok
end

-- Get a safe font path (with fallback)
function Theme:GetFont(fontType)
    local path = self.Fonts[fontType]
    if path and FontExists(path) then
        return path
    end
    -- Fallback chain
    if self.Fonts.PROPORTIONAL and FontExists(self.Fonts.PROPORTIONAL) then
        return self.Fonts.PROPORTIONAL
    end
    -- Ultimate fallback to game default
    return "Fonts\\FRIZQT__.TTF"
end

-- Apply label font (accent-colored monospace)
function Theme:ApplyLabelFont(fontString, size)
    if not fontString or not fontString.SetFont then return end
    local font = self:GetFont("LABEL")
    pcall(fontString.SetFont, fontString, font, size or 12, "")
    local r, g, b = self:GetAccentColor()
    if fontString.SetTextColor then
        fontString:SetTextColor(r, g, b, 1)
    end
end

-- Apply header font (bold accent-colored monospace)
function Theme:ApplyHeaderFont(fontString, size)
    if not fontString or not fontString.SetFont then return end
    local font = self:GetFont("HEADER")
    pcall(fontString.SetFont, fontString, font, size or 16, "")
    local r, g, b = self:GetAccentColor()
    if fontString.SetTextColor then
        fontString:SetTextColor(r, g, b, 1)
    end
end

-- Apply value font (white monospace)
function Theme:ApplyValueFont(fontString, size)
    if not fontString or not fontString.SetFont then return end
    local font = self:GetFont("VALUE")
    pcall(fontString.SetFont, fontString, font, size or 12, "")
    if fontString.SetTextColor then
        fontString:SetTextColor(1, 1, 1, 1)
    end
end

-- Apply button font (accent-colored monospace)
function Theme:ApplyButtonFont(fontString, size)
    if not fontString or not fontString.SetFont then return end
    local font = self:GetFont("BUTTON")
    pcall(fontString.SetFont, fontString, font, size or 13, "")
    local r, g, b = self:GetAccentColor()
    if fontString.SetTextColor then
        fontString:SetTextColor(r, g, b, 1)
    end
end

-- Apply dim text (secondary labels)
function Theme:ApplyDimFont(fontString, size)
    if not fontString or not fontString.SetFont then return end
    local font = self:GetFont("VALUE")
    pcall(fontString.SetFont, fontString, font, size or 11, "")
    if fontString.SetTextColor then
        fontString:SetTextColor(self.TEXT_DIM.r, self.TEXT_DIM.g, self.TEXT_DIM.b, self.TEXT_DIM.a)
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

-- Ensure UI namespace is properly set up when addon loads
function Theme:Initialize()
    -- Nothing special needed yet; accent color defaults are handled via AceDB
end

--------------------------------------------------------------------------------
-- Setting Patterns: Reusable relationships between settings
--------------------------------------------------------------------------------
-- Centralized definitions for common setting dependencies across the addon.
-- Use these patterns instead of one-off helper functions in renderers.
--
-- Usage in renderers:
--   local Patterns = addon.UI.SettingPatterns
--   local values, order = Patterns.Orientation.getDirectionOptions(currentOrientation)
--   local label = Patterns.Orientation.getColumnsLabel(currentOrientation)
--------------------------------------------------------------------------------

addon.UI.SettingPatterns = {}
local Patterns = addon.UI.SettingPatterns

--------------------------------------------------------------------------------
-- Orientation-Dependent Patterns
--------------------------------------------------------------------------------
-- Many Edit Mode systems have orientation (H/V) that affects:
--   - Available direction options (Left/Right vs Up/Down)
--   - Label text for columns/rows settings
--   - Description text
-- Used by: Essential Cooldowns, Utility Cooldowns, Tracked Buffs, Action Bars, etc.

Patterns.Orientation = {}

-- Get direction selector options based on orientation
-- @param orientation: "H" (horizontal) or "V" (vertical)
-- @return values (table), order (array)
function Patterns.Orientation.getDirectionOptions(orientation)
    if orientation == "V" then
        return { up = "Up", down = "Down" }, { "down", "up" }
    else
        return { left = "Left", right = "Right" }, { "right", "left" }
    end
end

-- Get default direction value for an orientation
-- @param orientation: "H" or "V"
-- @return default direction key
function Patterns.Orientation.getDefaultDirection(orientation)
    if orientation == "V" then
        return "down"
    else
        return "right"
    end
end

-- Get columns/rows label based on orientation
-- @param orientation: "H" or "V"
-- @return label string
function Patterns.Orientation.getColumnsLabel(orientation)
    if orientation == "V" then
        return "# Rows"
    else
        return "# Columns"
    end
end

-- Get columns/rows description based on orientation
-- @param orientation: "H" or "V"
-- @return description string
function Patterns.Orientation.getColumnsDescription(orientation)
    if orientation == "V" then
        return "Number of icons per column before wrapping to the next column."
    else
        return "Number of icons per row before wrapping to the next row."
    end
end

--------------------------------------------------------------------------------
-- Visibility-Dependent Patterns
--------------------------------------------------------------------------------
-- Some components have visibility modes that affect available sub-options.
-- Used by: Various component visibility settings

Patterns.Visibility = {}

-- Standard visibility mode options
function Patterns.Visibility.getModeOptions()
    return {
        always = "Always Show",
        combat = "Only in Combat",
        nocombat = "Only Out of Combat",
        never = "Never Show",
    }, { "always", "combat", "nocombat", "never" }
end

--------------------------------------------------------------------------------
-- Growth Direction Patterns (for icon wrap behavior)
--------------------------------------------------------------------------------
-- Icon wrap direction options that depend on primary direction
-- Used by: Cooldown viewers, buff frames

Patterns.IconWrap = {}

-- Get wrap direction options based on primary direction
-- @param primaryDirection: "left", "right", "up", or "down"
-- @return values (table), order (array)
function Patterns.IconWrap.getWrapOptions(primaryDirection)
    if primaryDirection == "left" or primaryDirection == "right" then
        -- Horizontal primary → vertical wrap options
        return { up = "Up", down = "Down" }, { "down", "up" }
    else
        -- Vertical primary → horizontal wrap options
        return { left = "Left", right = "Right" }, { "right", "left" }
    end
end

-- Get default wrap direction based on primary direction
function Patterns.IconWrap.getDefaultWrap(primaryDirection)
    if primaryDirection == "left" or primaryDirection == "right" then
        return "down"
    else
        return "right"
    end
end
