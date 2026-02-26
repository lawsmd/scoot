-- Helpers.lua - Shared helpers for Unit Frame TUI renderers
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames

--------------------------------------------------------------------------------
-- Unit Key Mapping
--------------------------------------------------------------------------------

-- Map componentId to unit key for database access
local UNIT_KEY_MAP = {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus = "Focus",
    ufPet = "Pet",
    ufToT = "TargetOfTarget",
    ufBoss = "Boss",
}

function UF.getUnitKey(componentId)
    return UNIT_KEY_MAP[componentId]
end

--------------------------------------------------------------------------------
-- Database Access
--------------------------------------------------------------------------------

-- Ensure unit frame database exists and return it
function UF.ensureUFDB(unitKey)
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    db.unitFrames = db.unitFrames or {}
    db.unitFrames[unitKey] = db.unitFrames[unitKey] or {}
    return db.unitFrames[unitKey]
end

-- Ensure text settings sub-table exists
function UF.ensureTextDB(unitKey, textKey)
    local t = UF.ensureUFDB(unitKey)
    if not t then return nil end
    t[textKey] = t[textKey] or {}
    return t[textKey]
end

-- Ensure portrait settings sub-table exists
function UF.ensurePortraitDB(unitKey)
    local t = UF.ensureUFDB(unitKey)
    if not t then return nil end
    t.portrait = t.portrait or {}
    return t.portrait
end

-- Ensure cast bar settings sub-table exists
function UF.ensureCastBarDB(unitKey)
    local t = UF.ensureUFDB(unitKey)
    if not t then return nil end
    t.castBar = t.castBar or {}
    return t.castBar
end

-- Ensure misc settings sub-table exists
function UF.ensureMiscDB(unitKey)
    local t = UF.ensureUFDB(unitKey)
    if not t then return nil end
    t.misc = t.misc or {}
    return t.misc
end

--------------------------------------------------------------------------------
-- Apply Functions
--------------------------------------------------------------------------------

function UF.applyBarTextures(unitKey)
    if addon.ApplyUnitFrameBarTexturesFor then
        addon.ApplyUnitFrameBarTexturesFor(unitKey)
    end
end

function UF.applyHealthText(unitKey)
    if addon.ApplyUnitFrameHealthTextVisibilityFor then
        addon.ApplyUnitFrameHealthTextVisibilityFor(unitKey)
    end
end

function UF.applyPowerText(unitKey)
    if addon.ApplyUnitFramePowerTextVisibilityFor then
        addon.ApplyUnitFramePowerTextVisibilityFor(unitKey)
    end
end

function UF.applyPortrait(unitKey)
    if addon.ApplyUnitFramePortraitFor then
        addon.ApplyUnitFramePortraitFor(unitKey)
    end
end

function UF.applyCastBar(unitKey)
    if addon.ApplyUnitFrameCastBarFor then
        addon.ApplyUnitFrameCastBarFor(unitKey)
    end
end

function UF.applyVisibility(unitKey)
    if addon.ApplyUnitFrameVisibilityFor then
        addon.ApplyUnitFrameVisibilityFor(unitKey)
    end
end

function UF.applyScaleMult(unitKey)
    if addon.ApplyUnitFrameScaleMultFor then
        addon.ApplyUnitFrameScaleMultFor(unitKey)
    end
end

function UF.applyStyles()
    if addon and addon.ApplyStyles then
        addon:ApplyStyles()
    end
end

--------------------------------------------------------------------------------
-- Edit Mode Integration
--------------------------------------------------------------------------------

-- Get the unit frame from Edit Mode system
function UF.getUnitFrame(componentId)
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end

    local idx = nil
    if componentId == "ufPlayer" then idx = EM.Player
    elseif componentId == "ufTarget" then idx = EM.Target
    elseif componentId == "ufFocus" then idx = EM.Focus
    elseif componentId == "ufPet" then idx = EM.Pet
    end

    if not idx then return nil end
    return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
end

-- Read Edit Mode Frame Size setting
function UF.getEditModeFrameSize(componentId)
    local frame = UF.getUnitFrame(componentId)
    local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.FrameSize
    if frame and settingId and addon and addon.EditMode and addon.EditMode.GetSetting then
        local v = addon.EditMode.GetSetting(frame, settingId)
        -- Edit Mode stores as 0-20 (where value maps to 100-200%)
        if v and v <= 20 then return 100 + (v * 5) end
        return math.max(100, math.min(200, v or 100))
    end
    return 100
end

-- Write Edit Mode Frame Size setting
function UF.setEditModeFrameSize(componentId, value)
    local frame = UF.getUnitFrame(componentId)
    local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.FrameSize
    if frame and settingId and addon and addon.EditMode and addon.EditMode.WriteSetting then
        addon.EditMode.WriteSetting(frame, settingId, value, {
            suspendDuration = 0.25,
        })
    end
    -- Reapply scale multiplier after Edit Mode scale change
    local unitKey = UF.getUnitKey(componentId)
    if unitKey then
        C_Timer.After(0.3, function()
            UF.applyScaleMult(unitKey)
        end)
    end
end

-- Read Edit Mode "Use Larger Frame" setting (Focus only)
function UF.getUseLargerFrame(componentId)
    local frame = UF.getUnitFrame(componentId)
    local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.UseLargerFrame
    if frame and settingId and addon and addon.EditMode and addon.EditMode.GetSetting then
        local v = addon.EditMode.GetSetting(frame, settingId)
        return (v and v ~= 0) and true or false
    end
    return false
end

-- Write Edit Mode "Use Larger Frame" setting
function UF.setUseLargerFrame(componentId, value)
    local frame = UF.getUnitFrame(componentId)
    local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.UseLargerFrame
    local val = (value and true) and 1 or 0
    if frame and settingId and addon and addon.EditMode and addon.EditMode.WriteSetting then
        addon.EditMode.WriteSetting(frame, settingId, val, {
            suspendDuration = 0.25,
        })
    end
end

--------------------------------------------------------------------------------
-- Info Icon Tooltips
--------------------------------------------------------------------------------

UF.TOOLTIPS = {
    hideBlizzardArt = {
        title = "Required Setting",
        text = "Hides Blizzard's default frame borders, overlays, and flash effects (aggro glow, reputation color, etc.). Required for Scoot's custom bar borders to display.",
    },
    frameSize = {
        title = "Edit Mode Scale",
        text = "This is Blizzard's Edit Mode scale setting (max 200%). If you need larger frames for handheld or accessibility use, the Scale Multiplier below can increase size beyond this limit.",
    },
    scaleMult = {
        title = "Addon Scale Multiplier",
        text = "This addon-only multiplier layers on top of Edit Mode's scale. A 1.5x multiplier combined with Edit Mode's 200% produces an effective 300% scale. Use this for ScooterDeck or other large-UI needs.",
    },
    offScreenDragging = {
        title = "Steam Deck / Large UI",
        text = "Allows moving the Unit Frame closer to the edge of the screen than is normally allowed in Edit Mode, intended for Steam Deck or similar handheld UIs. On a normally-sized screen, this setting is likely unnecessary.",
    },
    visibilityPriority = {
        title = "Opacity Priority",
        text = "Opacity priority: With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
    },
    hideOverAbsorbGlow = {
        title = "Absorb Shield Glow",
        text = "Hides the glow effect on the edge of your health bar that appears when you have an absorb shield providing effective health in excess of your maximum health.",
    },
}

--------------------------------------------------------------------------------
-- Selector/Dropdown Options
--------------------------------------------------------------------------------

-- Font style options
UF.fontStyleValues = {
    NONE = "Regular",
    OUTLINE = "Outline",
    THICKOUTLINE = "Thick Outline",
    HEAVYTHICKOUTLINE = "Heavy Thick Outline",
    SHADOW = "Shadow",
    SHADOWOUTLINE = "Shadow Outline",
    SHADOWTHICKOUTLINE = "Shadow Thick Outline",
}
UF.fontStyleOrder = { "NONE", "OUTLINE", "THICKOUTLINE", "HEAVYTHICKOUTLINE", "SHADOW", "SHADOWOUTLINE", "SHADOWTHICKOUTLINE" }

-- Text alignment options
UF.alignmentValues = {
    LEFT = "Left",
    CENTER = "Center",
    RIGHT = "Right",
}
UF.alignmentOrder = { "LEFT", "CENTER", "RIGHT" }

-- Bar color mode options (health)
UF.healthColorValues = {
    default = "Default",
    texture = "Texture Original",
    class = "Class Color",
    value = "Color by Value",
    valueDark = "Color by Value (Dark)",
    custom = "Custom",
}
UF.healthColorOrder = { "default", "texture", "class", "value", "valueDark", "custom" }

UF.healthColorInfoIcons = {
    valueDark = {
        tooltipText = "Dark bar at full health. Below 100%, uses the standard Color by Value color curve.",
    },
}

-- Bar color mode options (power)
UF.powerColorValues = {
    default = "Default",
    texture = "Texture Original",
    custom = "Custom",
}
UF.powerColorOrder = { "default", "texture", "custom" }

-- Background color mode options
UF.bgColorValues = {
    default = "Default",
    texture = "Texture Original",
    custom = "Custom",
}
UF.bgColorOrder = { "default", "texture", "custom" }

-- Portrait border style options
UF.portraitBorderValues = {
    texture_c = "Circle",
    texture_s = "Circle with Corner",
    rare_c = "Rare (Circle)",
    rare_s = "Rare (Square)",
}
UF.portraitBorderOrder = { "texture_c", "texture_s", "rare_c", "rare_s" }

-- Portrait border color mode options
UF.portraitBorderColorValues = {
    texture = "Texture Original",
    class = "Class Color",
    custom = "Custom",
}
UF.portraitBorderColorOrder = { "texture", "class", "custom" }

-- Health bar fill direction options (Target/Focus)
UF.fillDirectionValues = {
    default = "Left to Right (Default)",
    reverse = "Right to Left (Mirrored)",
}
UF.fillDirectionOrder = { "default", "reverse" }

-- Font color mode options
UF.fontColorValues = {
    default = "Default",
    class = "Class Color",
    custom = "Custom",
}
UF.fontColorOrder = { "default", "class", "custom" }

-- Font color mode options (power bar texts - adds Class Power Color)
UF.fontColorPowerValues = {
    default = "Default",
    class = "Class Color",
    classPower = "Class Power Color",
    custom = "Custom",
}
UF.fontColorPowerOrder = { "default", "class", "classPower", "custom" }

--------------------------------------------------------------------------------
-- Build Bar Border Options from addon
--------------------------------------------------------------------------------

function UF.buildBarBorderOptions()
    local values = { none = "None" }
    local order = { "none" }

    if addon and addon.BuildBarBorderOptionsContainer then
        local base = addon.BuildBarBorderOptionsContainer()
        if type(base) == "table" then
            for _, entry in ipairs(base) do
                if entry and entry.value and entry.text then
                    values[entry.value] = entry.text
                    table.insert(order, entry.value)
                end
            end
        end
    else
        -- Fallback
        values.square = "Default (Square)"
        table.insert(order, "square")
    end

    return values, order
end

--------------------------------------------------------------------------------
-- Build Icon Border Options from addon (for buff/debuff icons, etc.)
--------------------------------------------------------------------------------

function UF.buildIconBorderOptions()
    local values = { square = "Default (Square)" }
    local order = { "square" }

    if addon.IconBorders and addon.IconBorders.GetDropdownEntries then
        local data = addon.IconBorders.GetDropdownEntries()
        if data and #data > 0 then
            values = {}
            order = {}
            for _, entry in ipairs(data) do
                local key = entry.value or entry.key
                local label = entry.text or entry.label or key
                if key then
                    values[key] = label
                    table.insert(order, key)
                end
            end
        end
    end

    return values, order
end

--------------------------------------------------------------------------------
-- Common Tab Definitions
--------------------------------------------------------------------------------
-- Returns tab configurations for various sections

-- Health Bar tabs by unit type
function UF.getHealthBarTabs(componentId)
    if componentId == "ufTarget" or componentId == "ufFocus" then
        return {
            { key = "sizing", label = "Sizing" },
            { key = "direction", label = "Direction" },
            { key = "style", label = "Style" },
            { key = "border", label = "Border" },
            { key = "visibility", label = "Visibility" },
            { key = "percentText", label = "% Text" },
            { key = "valueText", label = "Value Text" },
        }
    elseif componentId == "ufPlayer" then
        return {
            { key = "sizing", label = "Sizing" },
            { key = "style", label = "Style" },
            { key = "border", label = "Border" },
            { key = "visibility", label = "Visibility" },
            { key = "percentText", label = "% Text" },
            { key = "valueText", label = "Value Text" },
        }
    else -- Pet
        return {
            { key = "style", label = "Style" },
            { key = "border", label = "Border" },
            { key = "percentText", label = "% Text" },
            { key = "valueText", label = "Value Text" },
        }
    end
end

-- Power Bar tabs (same for all units)
function UF.getPowerBarTabs()
    return {
        { key = "positioning", label = "Positioning" },
        { key = "sizing", label = "Sizing" },
        { key = "style", label = "Style" },
        { key = "border", label = "Border" },
        { key = "visibility", label = "Visibility" },
        { key = "percentText", label = "% Text" },
        { key = "valueText", label = "Value Text" },
    }
end

-- Portrait tabs by unit type
function UF.getPortraitTabs(componentId)
    local hasPersonalText = (componentId == "ufPlayer" or componentId == "ufPet")
    if hasPersonalText then
        return {
            { key = "positioning", label = "Positioning" },
            { key = "sizing", label = "Sizing" },
            { key = "mask", label = "Mask" },
            { key = "border", label = "Border" },
            { key = "personalText", label = "Personal Text" },
            { key = "visibility", label = "Visibility" },
        }
    else
        return {
            { key = "positioning", label = "Positioning" },
            { key = "sizing", label = "Sizing" },
            { key = "mask", label = "Mask" },
            { key = "border", label = "Border" },
            { key = "visibility", label = "Visibility" },
        }
    end
end

-- Cast Bar tabs by unit type
function UF.getCastBarTabs(componentId)
    if componentId == "ufPlayer" then
        -- Player has Cast Time tab
        return {
            { key = "positioning", label = "Positioning" },
            { key = "sizing", label = "Sizing" },
            { key = "style", label = "Style" },
            { key = "border", label = "Border" },
            { key = "icon", label = "Icon" },
            { key = "spellName", label = "Spell Name" },
            { key = "castTime", label = "Cast Time" },
            { key = "visibility", label = "Visibility" },
        }
    else
        -- Target/Focus: 7 tabs (no Cast Time)
        return {
            { key = "positioning", label = "Positioning" },
            { key = "sizing", label = "Sizing" },
            { key = "style", label = "Style" },
            { key = "border", label = "Border" },
            { key = "icon", label = "Icon" },
            { key = "spellName", label = "Spell Name" },
            { key = "visibility", label = "Visibility" },
        }
    end
end

-- Class Resource tabs (Player only)
function UF.getClassResourceTabs()
    return {
        { key = "styling", label = "Styling" },
        { key = "text", label = "Text" },
        { key = "positioning", label = "Positioning" },
    }
end

-- Buffs & Debuffs tabs (Target/Focus)
function UF.getBuffsDebuffsTabs()
    return {
        { key = "sizing", label = "Sizing" },
        { key = "border", label = "Border" },
        { key = "visibility", label = "Visibility" },
        { key = "filters", label = "Filters" },
    }
end

--------------------------------------------------------------------------------
-- Return module
--------------------------------------------------------------------------------

return UF
