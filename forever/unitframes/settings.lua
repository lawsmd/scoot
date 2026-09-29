--------------------------------------------------------------------------------
-- forever/unitframes/settings.lua
-- The aura row and health bar settings of the Classic unit frames: their
-- defaults, which frames have which, and the refresh the pages call.
--
-- On both clients, like text.lua, because page.lua draws on retail where no
-- frame is built. The HUD halves are auras.lua and healprediction.lua, which
-- the beta alone loads; the refreshes below are no-ops without them.
--
-- The defaults are vanilla's. The target and focus show every buff and every
-- debuff, the target of target and the pet four debuffs, and the player none:
-- vanilla's player auras sit in BuffFrame, off the frame. Every icon is the
-- large size, 21, which is vanilla with showDynamicBuffSize off; the small
-- size for other casters' auras needs a per-aura read the container keeps to
-- itself (auras.lua).
--------------------------------------------------------------------------------

local addonName, addon = ...

local UF = addon.UnitFrames
local DB = addon.DB
local Text = UF.Text

local Settings = {}
UF.Settings = Settings

-- What each frame's aura rows and health bar offer its page. "full" is a buff
-- row and a debuff row that wrap; "debuffs" is the small frames' fixed set.
-- health is the heal prediction. The target of target has no heal prediction
-- in vanilla, and no bar numbers; its bar still takes a texture and a color.
Settings.SURFACE = {
    player       = { auras = "full", health = true, barText = true },
    target       = { auras = "full", health = true, barText = true },
    focus        = { auras = "full", health = true, barText = true },
    targettarget = { auras = "debuffs" },
    pet          = { auras = "debuffs", health = true, barText = true },
}

-- Vanilla's numbers, per frame: the icon, the cap, and the wrap width.
Settings.AURA_DEFAULTS = {
    player       = { enabled = false, iconSize = 21, buffs = 32, debuffs = 16, rowWidth = 122 },
    target       = { enabled = true, iconSize = 21, buffs = 32, debuffs = 16, rowWidth = 122 },
    focus        = { enabled = true, iconSize = 21, buffs = 32, debuffs = 16, rowWidth = 122 },
    targettarget = { enabled = true, iconSize = 12, debuffs = 4 },
    pet          = { enabled = true, iconSize = 15, debuffs = 4 },
}

Settings.MAX_BUFFS = 32
Settings.MAX_DEBUFFS = 16
Settings.MAX_SMALL_DEBUFFS = 4

--- Text.Path("player", "auras", "iconSize") and its siblings.
function Settings.AuraPath(key, ...)
    return Text.Path(key, "auras", ...)
end

function Settings.HealthPath(key, ...)
    return Text.Path(key, "health", ...)
end

--- A bar's own settings: Settings.BarPath("player", "health", "texture"),
--- or ("target", "power", "text", "value", "show").
function Settings.BarPath(key, bar, ...)
    return Text.Path(key, bar, ...)
end

function Settings.Bar(key, bar, ...)
    return DB.Get(Settings.BarPath(key, bar, ...))
end

-- The two strings each bar can carry, and the bars that carry them.
Settings.BAR_TEXT_SLOTS = { "value", "percent" }
Settings.TEXT_BARS = { "health", "power" }

function Settings.Aura(key, ...)
    return DB.Get(Settings.AuraPath(key, ...))
end

function Settings.Health(key, ...)
    return DB.Get(Settings.HealthPath(key, ...))
end

do
    local map = {}
    for _, key in ipairs(UF.ORDER) do
        local d = Settings.AURA_DEFAULTS[key]
        local function set(value, ...) map[Settings.AuraPath(key, ...)] = value end
        set(d.enabled, "enabled")
        set(d.iconSize, "iconSize")
        set(0, "shape")
        set(true, "swipe")
        set(true, "tooltips")
        set(true, "debuffs", "show")
        set(d.debuffs, "debuffs", "max")
        set(false, "debuffs", "onlyMine")
        set(true, "debuffs", "dispelColors")
        if d.buffs then
            set(true, "buffs", "show")
            set(d.buffs, "buffs", "max")
            set(false, "buffs", "onlyMine")
            set(true, "buffs", "stealable")
            -- Vanilla's buffsOnTop is off: the rows hang below the frame.
            set("below", "position")
            set(d.rowWidth, "rowWidth")
        end
        -- No face, size or style stored reads NumberFontNormalSmall as it is.
        set(false, "count", "hidden")
        set({ 1, 1, 1, 1 }, "count", "color")
        set(0, "count", "offsetX")
        set(0, "count", "offsetY")

        if Settings.SURFACE[key].health then
            local function hp(value, field) map[Settings.HealthPath(key, field)] = value end
            hp(true, "incomingHeals")
            hp(true, "absorb")
            hp(true, "overAbsorbGlow")
            hp(true, "healAbsorb")
        end
        -- Vanilla's bar: UI-StatusBar in green. "default" is both.
        local function bar(value, ...) map[Settings.BarPath(key, "health", ...)] = value end
        bar("default", "texture")
        bar("default", "colorMode")
        bar({ 0, 1, 0, 1 }, "color")
        bar(false, "hideTextureOnly")
        if Settings.SURFACE[key].barText then
            -- The current value at all times and no percent, which is what
            -- the frames showed before these settings. Vanilla's own is the
            -- statusText CVar off: "current / max" on mouseover. No face,
            -- size or style stored reads TextStatusBarText as it is.
            for _, barKey in ipairs(Settings.TEXT_BARS) do
                local function text(value, slot, field)
                    map[Settings.BarPath(key, barKey, "text", slot, field)] = value
                end
                text("always", "value", "show")
                text("never", "percent", "show")
                text("current", "value", "format")
                for _, slot in ipairs(Settings.BAR_TEXT_SLOTS) do
                    text("default", slot, "colorMode")
                    text({ 1, 1, 1, 1 }, slot, "color")
                    text(0, slot, "offsetX")
                    text(0, slot, "offsetY")
                end
            end
        end
    end
    DB.RegisterDefaults(map)
end

--- Re-apply one frame's aura rows, or every frame's. The page's apply.
function UF.RefreshAuras(key)
    if not (UF.Auras and UF.Frames) then return end
    for k, inst in pairs(UF.Frames) do
        if key == nil or k == key then UF.Auras.Apply(inst) end
    end
end

--- Re-apply one frame's bar numbers, or every frame's: their placement and
--- font, then what they show.
function UF.RefreshBarText(key)
    local Values = UF.Values
    if not (Values and UF.Frames) then return end
    for k, inst in pairs(UF.Frames) do
        if key == nil or k == key then
            Text.ApplyBarTexts(inst)
            if not inst.previewStandIn then
                Values.ApplyBarTextShown(inst)
                Values.ApplyBarText(inst)
            end
        end
    end
end

--- Re-apply one frame's health bar texture and color, or every frame's.
function UF.RefreshBarStyle(key)
    local Values = UF.Values
    if not (Values and UF.Frames) then return end
    for k, inst in pairs(UF.Frames) do
        if key == nil or k == key then
            Values.ApplyHealthStyle(inst)
            UF.Frame.PaintAll(inst)
        end
    end
end

--- Re-apply one frame's heal prediction and absorbs, or every frame's.
function UF.RefreshHealth(key)
    if not (UF.HealPrediction and UF.Frames) then return end
    for k, inst in pairs(UF.Frames) do
        if key == nil or k == key then UF.HealPrediction.Apply(inst) end
    end
end
