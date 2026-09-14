-- SettingPatterns.lua - reusable relationships between settings.
-- Centralized definitions for common setting dependencies across the addon.
-- Use these patterns instead of one-off helper functions in renderers.
--
-- Usage in renderers:
--   local Patterns = addon.UI.SettingPatterns
--   local values, order = Patterns.Orientation.getDirectionOptions(currentOrientation)
--   local label = Patterns.Orientation.getColumnsLabel(currentOrientation)
local addonName, addon = ...

addon.UI = addon.UI or {}
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
