-- Helpers.lua - Shared helpers for Unit Frame TUI renderers
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames

--------------------------------------------------------------------------------
-- Unit Key Mapping
--------------------------------------------------------------------------------

-- Map componentId to unit key for database access (shared catalog, refactor #22)
local UNIT_KEY_MAP = addon.Frames.UNIT_KEY_BY_COMPONENT

function UF.getUnitKey(componentId)
    return UNIT_KEY_MAP[componentId]
end

--------------------------------------------------------------------------------
-- Database Access (read-only — use in get callbacks to avoid materializing tables)
--------------------------------------------------------------------------------

function UF.getUFDB(unitKey)
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    local unitFrames = rawget(db, "unitFrames")
    return unitFrames and rawget(unitFrames, unitKey) or nil
end

function UF.getTextDB(unitKey, textKey)
    local t = UF.getUFDB(unitKey)
    return t and rawget(t, textKey) or nil
end

function UF.getPortraitDB(unitKey)
    local t = UF.getUFDB(unitKey)
    return t and rawget(t, "portrait") or nil
end

function UF.getCastBarDB(unitKey)
    local t = UF.getUFDB(unitKey)
    return t and rawget(t, "castBar") or nil
end

function UF.getMiscDB(unitKey)
    local t = UF.getUFDB(unitKey)
    return t and rawget(t, "misc") or nil
end

function UF.getBuffsDebuffsDB(unitKey)
    local t = UF.getUFDB(unitKey)
    return t and rawget(t, "buffsDebuffs") or nil
end

--------------------------------------------------------------------------------
-- Database Access (write — materializes tables, use only in set callbacks)
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

-- Ensure buffs/debuffs settings sub-table exists
function UF.ensureBuffsDebuffsDB(unitKey)
    local t = UF.ensureUFDB(unitKey)
    if not t then return nil end
    t.buffsDebuffs = t.buffsDebuffs or {}
    return t.buffsDebuffs
end

--------------------------------------------------------------------------------
-- Apply Functions
--------------------------------------------------------------------------------

-- Kept off addon.Refresh: one function each, no ordering to keep.
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

function UF.applyNameLevelText(unitKey)
    if addon.ApplyUnitFrameNameLevelTextFor then
        addon.ApplyUnitFrameNameLevelTextFor(unitKey)
    end
    UF.applyStyles()
end

function UF.applyBuffsDebuffs(unitKey)
    if addon.ApplyUnitFrameBuffsDebuffsFor then
        addon.ApplyUnitFrameBuffsDebuffsFor(unitKey)
    end
end

--------------------------------------------------------------------------------
-- Composite Text Accessors
--------------------------------------------------------------------------------
-- get/set closure pairs speaking AddTextStyleBlock's field vocabulary
-- (see settings/BuilderComposites.lua). get is read-only; set materializes.

-- Accessors for a unit's text sub-table (textHealthPercent, textName, ...).
-- The hidden flag lives on the parent unit table under a key derived from
-- textKey (textHealthPercent -> healthPercentHidden) unless opts.hiddenKey
-- overrides (name/level text uses nameTextHidden/levelTextHidden).
-- offsetX/offsetY map to the nested offset.x/offset.y pair.
function UF.textAccessors(unitKey, textKey, opts)
    local hiddenKey = opts and opts.hiddenKey
    if not hiddenKey then
        local stripped = textKey:gsub("^text", "")
        hiddenKey = stripped:sub(1, 1):lower() .. stripped:sub(2) .. "Hidden"
    end
    local function get(field)
        if field == "hidden" then
            local t = UF.getUFDB(unitKey)
            return t and rawget(t, hiddenKey)
        end
        local s = UF.getTextDB(unitKey, textKey)
        if not s then return nil end
        if field == "offsetX" or field == "offsetY" then
            local o = s.offset
            return o and o[field == "offsetX" and "x" or "y"]
        end
        return s[field]
    end
    local function set(field, value)
        if field == "hidden" then
            local t = UF.ensureUFDB(unitKey)
            if t then t[hiddenKey] = value end
            return
        end
        local s = UF.ensureTextDB(unitKey, textKey)
        if not s then return end
        if field == "offsetX" or field == "offsetY" then
            s.offset = s.offset or {}
            s.offset[field == "offsetX" and "x" or "y"] = value
        else
            s[field] = value
        end
    end
    return get, set
end

-- Accessors for a cast bar text sub-table (spellNameText, castTimeText).
function UF.castBarTextAccessors(unitKey, tableKey)
    local function get(field)
        local cb = UF.getCastBarDB(unitKey)
        local s = cb and rawget(cb, tableKey)
        if not s then return nil end
        return s[field]
    end
    local function set(field, value)
        local cb = UF.ensureCastBarDB(unitKey)
        if not cb then return end
        cb[tableKey] = cb[tableKey] or {}
        cb[tableKey][field] = value
    end
    return get, set
end

-- Accessors for a bar's prefixed key family (healthBarTexture,
-- healthBarBorderInsetH, ...) as AddBarStyleBlock and AddBarBorderBlock
-- consume them. The unit table by default; opts.store = "castBar" reads and
-- writes the cast bar sub-table. opts.suffixes overrides single suffixes (the
-- name backdrop stores its enable flag as BorderEnabled).
function UF.barAccessors(unitKey, barPrefix, opts)
    local Helpers = addon.UI.Settings.Helpers
    local getTable, ensureTable
    if opts and opts.store == "castBar" then
        getTable = function() return UF.getCastBarDB(unitKey) end
        ensureTable = function() return UF.ensureCastBarDB(unitKey) end
    else
        getTable = function() return UF.getUFDB(unitKey) end
        ensureTable = function() return UF.ensureUFDB(unitKey) end
    end
    return Helpers.CreateBarAccessors(getTable, ensureTable, barPrefix, opts)
end

-- The unit's state opacity triple (opacityInCombat, opacityWithTarget,
-- opacityOutOfCombat) as AddStateOpacityBlock consumes it; the field-to-key
-- map is addon.Opacity.Keys.InCombat.
function UF.opacityAccessors(unitKey)
    local Helpers = addon.UI.Settings.Helpers
    return Helpers.CreateFlatAccessors(
        function(key) local t = UF.getUFDB(unitKey); return t and t[key] end,
        function(key, v) local t = UF.ensureUFDB(unitKey); if t then t[key] = v end end,
        addon.Opacity.Keys.InCombat)
end

-- The buffs/debuffs icon border family (borderEnable, borderStyle,
-- borderTintColor, ...) as AddIconBorderBlock consumes it; the sub-table is
-- read without materializing and materialized on write.
function UF.auraBorderAccessors(unitKey)
    local Helpers = addon.UI.Settings.Helpers
    return Helpers.CreateIconBorderAccessors(
        function(key) local t = UF.getBuffsDebuffsDB(unitKey); return t and t[key] end,
        function(key, v) local t = UF.ensureBuffsDebuffsDB(unitKey); if t then t[key] = v end end,
        "border")
end

--------------------------------------------------------------------------------
-- Bound Helpers
--------------------------------------------------------------------------------

-- Per-unit helpers bound by UF.BindUnit; each takes unitKey first.
local BIND_NAMES = {
    "ensureUFDB", "ensureTextDB", "ensurePortraitDB", "ensureCastBarDB",
    "ensureMiscDB", "ensureBuffsDebuffsDB",
    "getUFDB", "getTextDB", "getPortraitDB", "getCastBarDB", "getMiscDB",
    "getBuffsDebuffsDB",
    "applyBarTextures", "applyHealthText", "applyPowerText", "applyPortrait",
    "applyCastBar", "applyVisibility", "applyScaleMult", "applyNameLevelText",
    "applyBuffsDebuffs",
    "textAccessors", "castBarTextAccessors", "barAccessors", "opacityAccessors",
    "auraBorderAccessors",
}

-- Returns a table with the helpers above bound to unitKey, plus applyStyles.
-- Replaces the wrapper preambles in the unit frame renderers. overrides
-- replaces entries by name (Boss passes its own applyCastBar).
function UF.BindUnit(unitKey, overrides)
    local B = {}
    for _, name in ipairs(BIND_NAMES) do
        local fn = UF[name]
        B[name] = function(...)
            return fn(unitKey, ...)
        end
    end
    B.applyStyles = UF.applyStyles
    if overrides then
        for name, fn in pairs(overrides) do
            B[name] = fn
        end
    end
    return B
end

--------------------------------------------------------------------------------
-- Edit Mode Integration
--------------------------------------------------------------------------------

-- Get the unit frame from Edit Mode system. Strict on purpose: the consumers
-- below read/write Edit Mode settings, so ufToT/ufFocusTarget must keep
-- returning nil (they are not Edit Mode systems).
function UF.getUnitFrame(componentId)
    return addon.GetEditModeUnitFrame(UF.getUnitKey(componentId))
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

-- Read Edit Mode "Use Larger Frame" setting (Focus, Boss)
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
    hideOverAbsorbGlow = {
        title = "Absorb Shield Glow",
        text = "Hides the glow effect on the edge of your health bar that appears when you have an absorb shield providing effective health in excess of your maximum health.",
    },
}

--------------------------------------------------------------------------------
-- Selector/Dropdown Options
--------------------------------------------------------------------------------

-- Font style options; the catalog in core/fonts.lua is the source of truth.
UF.fontStyleValues = addon.FontStyles.values
UF.fontStyleOrder = addon.FontStyles.order
UF.fontStyleOrderPaired = addon.FontStyles.orderPaired

-- Dropdown option catalogs. core/catalogs.lua is the source of truth; these
-- names are aliases by reference so existing renderer reads stay put.
local Catalogs = addon.Catalogs

-- Alignment mode (bar-relative vs name-relative) and name-anchor positions
UF.alignmentModeValues = Catalogs.AlignmentMode.values
UF.alignmentModeOrder = Catalogs.AlignmentMode.order
UF.nameAnchorValues = Catalogs.NameAnchor.values
UF.nameAnchorOrder = Catalogs.NameAnchor.order

-- Bar color modes
UF.healthColorValues = Catalogs.ColorMode.Health.values
UF.healthColorOrder = Catalogs.ColorMode.Health.order
UF.healthColorInfoIcons = Catalogs.ColorMode.Health.infoIcons
UF.powerColorValues = Catalogs.ColorMode.Power.values
UF.powerColorOrder = Catalogs.ColorMode.Power.order
UF.castBarColorValues = Catalogs.ColorMode.CastBar.values
UF.castBarColorOrder = Catalogs.ColorMode.CastBar.order
UF.bgColorValues = Catalogs.ColorMode.Background.values
UF.bgColorOrder = Catalogs.ColorMode.Background.order

-- Portrait border style options
UF.portraitBorderValues = {
    texture_c = "Circle",
    texture_s = "Circle with Corner",
    rare_c = "Rare (Circle)",
    rare_s = "Rare (Square)",
}
UF.portraitBorderOrder = { "texture_c", "texture_s", "rare_c", "rare_s" }

UF.portraitBorderColorValues = Catalogs.ColorMode.PortraitBorder.values
UF.portraitBorderColorOrder = Catalogs.ColorMode.PortraitBorder.order

-- Text color modes
UF.fontColorCastBarValues = Catalogs.ColorMode.CastBarText.values
UF.fontColorCastBarOrder = Catalogs.ColorMode.CastBarText.order
UF.fontColorCastBarInfoIcons = Catalogs.ColorMode.CastBarText.infoIcons
UF.fontColorCastBarNonPlayerValues = Catalogs.ColorMode.CastBarTextNonPlayer.values
UF.fontColorCastBarNonPlayerOrder = Catalogs.ColorMode.CastBarTextNonPlayer.order
UF.fontColorHealthValues = Catalogs.ColorMode.TextHealth.values
UF.fontColorHealthOrder = Catalogs.ColorMode.TextHealth.order
UF.fontColorPowerValues = Catalogs.ColorMode.TextPower.values
UF.fontColorPowerOrder = Catalogs.ColorMode.TextPower.order

--------------------------------------------------------------------------------
-- Build Bar Border Options from addon
--------------------------------------------------------------------------------

-- Character-identical to the settings Helpers builder, which loads first.
UF.buildBarBorderOptions = addon.UI.Settings.Helpers.getBarBorderOptions

--------------------------------------------------------------------------------
-- Common Tab Definitions
--------------------------------------------------------------------------------
-- Returns tab configurations for various sections

-- Health Bar tabs by unit type
function UF.getHealthBarTabs(componentId)
    if componentId == "ufTarget" or componentId == "ufFocus" then
        return {
            { key = "style", label = "Style" },
            { key = "border", label = "Border" },
            { key = "visibility", label = "Visibility" },
            { key = "percentText", label = "% Text" },
            { key = "valueText", label = "Value Text" },
        }
    elseif componentId == "ufPlayer" then
        return {
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
            { key = "visibility", label = "Visibility" },
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
function UF.getCastBarTabs(componentId, options)
    local sparkTab = { key = "spark", label = "Spark", infoIcon = {
        tooltipTitle = "Cast Bar Spark",
        tooltipText = "The spark is the bright vertical line on the cast bar that marks the current cast progress position.",
    } }
    local fillLineTab = {
        key = "fillLine",
        label = "Text-Fill Mode",
        visible = options and options.fillLineVisible or nil,
    }
    if componentId == "ufPlayer" then
        -- Player has Cast Time tab
        return {
            { key = "positioning", label = "Positioning" },
            { key = "style", label = "Style" },
            sparkTab,
            { key = "border", label = "Border" },
            { key = "icon", label = "Icon" },
            { key = "spellName", label = "Spell Name" },
            { key = "castTime", label = "Cast Time" },
            fillLineTab,
            { key = "visibility", label = "Visibility" },
        }
    else
        -- Target/Focus/Boss
        return {
            { key = "positioning", label = "Positioning" },
            { key = "style", label = "Style" },
            sparkTab,
            { key = "border", label = "Border" },
            { key = "icon", label = "Icon" },
            { key = "spellName", label = "Spell Name" },
            { key = "castTime", label = "Cast Time" },
            fillLineTab,
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
