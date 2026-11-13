--------------------------------------------------------------------------------
-- forever/unitframes/settings.lua
-- The aura row and health bar settings of the unit frames, one set per style
-- of each frame: their defaults, which frames have which, and the refresh
-- the pages call.
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
-- cost is the mana cost of the spell being cast, which the Modern player
-- frame alone draws on its power bar (barsegments.lua); the page offers its
-- switch on that style.
Settings.SURFACE = {
    player       = { auras = "full", health = true, barText = true, cost = true },
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

--- The Portrait section's settings: Settings.Portrait("player", "zoom").
function Settings.PortraitPath(key, ...)
    return Text.Path(key, "portrait", ...)
end

function Settings.Portrait(key, ...)
    return DB.Get(Settings.PortraitPath(key, ...))
end

-- The pages with a Portrait Opacity row, the two Unit Frames X gives one.
Settings.PORTRAIT_OPACITY = { pet = true, targettarget = true }

--------------------------------------------------------------------------------
-- State opacity
--------------------------------------------------------------------------------
-- The Visibility section, on the two pages Unit Frames X gives one: the
-- frame's opacity in combat, with a target, and out of combat, in that order
-- of priority (core/opacity.lua). One set per style, under the catalog's
-- InCombat names. frame.lua's ApplyAlpha multiplies it into the frame's
-- alpha, under whatever Dynamic Layouts holds, and carries a change of state
-- there through the state fade.

Settings.STATE_OPACITY = { player = true, pet = true }

--- field is the composite's: "combat", "target" or "ooc".
function Settings.OpacityPath(key, field)
    return Text.Path(key, addon.Opacity.Keys.InCombat[field])
end

local opacityValues = {}

--- The alpha the Visibility section asks for now, and the state it answers
--- to; 1 and no state for a frame without the section.
function UF.StateAlpha(key)
    if not Settings.STATE_OPACITY[key] then return 1 end
    local keys = addon.Opacity.Keys.InCombat
    for _, name in pairs(keys) do
        opacityValues[name] = DB.Get(Text.Path(key, name))
    end
    return addon.Opacity.Resolve(opacityValues, keys)
end

--- Re-land one frame's alpha, or every frame's. The page's apply.
function UF.RefreshOpacity(key)
    if not (UF.Frame and UF.Frames) then return end
    for k, inst in pairs(UF.Frames) do
        if key == nil or k == key then UF.Frame.ApplyAlpha(inst) end
    end
end

--------------------------------------------------------------------------------
-- Misc
--------------------------------------------------------------------------------
-- The Misc section's switches, each offered where the frame draws the piece.
-- Static, since the page loads where no art spec does; the specs agree. A
-- frame's entry is true for every style, or the styles that draw it: the
-- Classic player frame has no PvP icon and no group plate.

Settings.MISC = {
    hidePvP = { label = "Hide PvP Icons",
                frames = { player = { modern = true }, target = true, focus = true } },
    hideGroupNumber = { label = "Hide Group Number",
                        frames = { player = { modern = true } } },
}
Settings.MISC_ORDER = { "hidePvP", "hideGroupNumber" }

--- Whether a frame's page offers a Misc switch on the style it draws.
function Settings.MiscOffered(key, style, field)
    local row = Settings.MISC[field]
    local frames = row and row.frames[key]
    return frames == true or (type(frames) == "table" and frames[style] == true)
end

function Settings.MiscPath(key, field)
    return Text.Path(key, "misc", field)
end

--- Whether a Misc switch is on for the style the frame draws.
function Settings.Misc(key, field)
    return DB.Get(Settings.MiscPath(key, field)) == true
end

--- Repaint one frame's state art after a Misc switch, or every frame's.
function UF.RefreshMisc(key)
    if not (UF.Frame and UF.Frames) then return end
    for k, inst in pairs(UF.Frames) do
        if key == nil or k == key then UF.Frame.PaintAll(inst) end
    end
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

--------------------------------------------------------------------------------
-- Style
--------------------------------------------------------------------------------
-- Which style a frame draws: Camelot, the Classic rebuild with Camelot's
-- touches; Classic, the same frame with Blizzard's values; or Modern, the
-- client's own frame. One setting per unit key (text.lua, UF.StyleOf), read
-- by Frame.Build and reconciled by UF.ApplyAll where the HUD is loaded; on
-- retail the pages write it and nothing reads it.

--- The page's write. The reconcile swaps the frame where the HUD is loaded;
--- on retail the stored value is the whole effect.
function UF.SetStyle(key, style)
    if not UF.STYLES[style] then return false end
    DB.Set(Text.Path(key, "style"), style)
    if UF.ApplyAll then UF.ApplyAll() end
    return true
end

--------------------------------------------------------------------------------
-- Attach
--------------------------------------------------------------------------------
-- A frame that hangs off another in place of a spot of its own: the target
-- of target on the target's right, level with it, where the Camelot layout
-- has always put it. The setting is the frame's whatever shape it draws
-- (text.lua, Text.SHARED), as the position is. On by default; the two
-- preset starts turn it off, since their spots are Blizzard's own.
-- editmode.lua applies it where the HUD is loaded; on retail the page
-- writes it and nothing reads it.

-- unit key -> the frame it hangs off, the anchor point on each, and the
-- labels: the page's, the dialog's, which has less room, and the host's
-- name for the page's description.
Settings.ATTACH = {
    targettarget = { to = "target", point = "LEFT", relPoint = "RIGHT",
                     label = "Attach to Target Frame", short = "Attach to Target",
                     hostName = "target frame" },
}

-- The target hung off the player frame until 4 November 2026. A profile
-- whose stored switch still reads on has its target frame's spot written
-- out as a position of its own, once (editmode.lua, CarryLegacyAttach), so
-- a target that followed a dragged player frame stays where it stood. The
-- old default and stock value stay registered for that one read.
Settings.LEGACY_ATTACH = {
    target = { to = "player", point = "LEFT", relPoint = "RIGHT" },
}

-- The offsets' reach either way, in the frame's own units.
Settings.ATTACH_OFFSET_RANGE = 200

--- "attach", "attachX" or "attachY": a frame's key, with no style prefix.
function Settings.AttachPath(key, field)
    return Text.StylePath(key, "camelot", field)
end

--- Whether the frame's attach setting is on. False for a frame that has
--- no host to hang off.
function UF.IsAttachOn(key)
    if not Settings.ATTACH[key] then return false end
    return DB.Get(Settings.AttachPath(key, "attach")) == true
end

--- The attach's x and y offsets, in the frame's own units.
function UF.AttachOffsets(key)
    return tonumber(DB.Get(Settings.AttachPath(key, "attachX"))) or 0,
           tonumber(DB.Get(Settings.AttachPath(key, "attachY"))) or 0
end

local function applyAttach(key)
    local EM = UF.EditMode
    if EM and EM.ApplyAttach then EM.ApplyAttach(key) end
end

--- The page's and the dialog's write of the switch.
function UF.SetAttach(key, on)
    if not Settings.ATTACH[key] then return false end
    DB.Set(Settings.AttachPath(key, "attach"), on and true or false)
    applyAttach(key)
    return true
end

--- The page's and the dialog's write of one offset, "x" or "y".
function UF.SetAttachOffset(key, axis, value)
    if not Settings.ATTACH[key] then return false end
    local r = Settings.ATTACH_OFFSET_RANGE
    local n = math.max(-r, math.min(r, tonumber(value) or 0))
    DB.Set(Settings.AttachPath(key, axis == "y" and "attachY" or "attachX"), n)
    applyAttach(key)
    return true
end

--------------------------------------------------------------------------------
-- Hide when targeting yourself
--------------------------------------------------------------------------------
-- Vanilla's other rule for the target of target: no frame while the target
-- is the player, whose target's target is the player again. No macro
-- conditional says so and the secure manager has no UnitIsUnit, so the
-- driver keeps the frame shown and tot.lua takes it to alpha 0 instead,
-- legal in combat on the protected frame. The frame's whatever shape it
-- draws (text.lua, Text.SHARED); on under every start, since vanilla and
-- the client both hide it.

-- The frames with the rule.
Settings.HIDE_WHEN_SELF = { targettarget = true }

function Settings.HideWhenSelfPath(key)
    return Text.StylePath(key, "camelot", "hideWhenSelf")
end

--- Whether the frame goes to alpha 0 while the target is the player.
function UF.HideWhenSelf(key)
    if not Settings.HIDE_WHEN_SELF[key] then return false end
    return DB.Get(Settings.HideWhenSelfPath(key)) ~= false
end

--- The page's write. The frame on screen re-reads its alpha where the HUD
--- is loaded; on retail the stored value is the whole effect.
function UF.SetHideWhenSelf(key, on)
    if not Settings.HIDE_WHEN_SELF[key] then return false end
    DB.Set(Settings.HideWhenSelfPath(key), on and true or false)
    local inst = UF.Frames and UF.Frames[key]
    if inst and UF.Frame and UF.Frame.ApplyAlpha then UF.Frame.ApplyAlpha(inst) end
    return true
end

--------------------------------------------------------------------------------
-- Combo points
--------------------------------------------------------------------------------
-- The target frame's row (combopoints.lua), one switch per style, on under
-- every start: this client draws vanilla's ComboFrame over its own target
-- frame, and Camelot parks that frame with the target.

Settings.COMBO_POINTS = { target = true }

--- Whether the frame shows its combo points, on the style it draws.
function UF.ShowComboPoints(key)
    if not Settings.COMBO_POINTS[key] then return false end
    return Text.Get(key, "comboPoints") ~= false
end

--- The page's write, to the style the frame is on.
function UF.SetComboPoints(key, on)
    if not Settings.COMBO_POINTS[key] then return false end
    DB.Set(Text.Path(key, "comboPoints"), on and true or false)
    local inst = UF.Frames and UF.Frames[key]
    if inst and UF.ComboPoints then UF.ComboPoints.Apply(inst) end
    return true
end

-- The defaults, one set per style of each frame, the same values in each
-- but the Classic style's bar numbers: each style's keys sit under its own
-- prefix (text.lua, "Paths and defaults"), so a value set on one style never
-- reaches another.
do
    local map = {}
    for _, key in ipairs(UF.ORDER) do
        -- Camelot ships the client's own frames, the owner's call of 22
        -- October 2026; a start from a preset, below, takes that preset's
        -- style.
        map[Text.StylePath(key, "camelot", "style")] = "modern"
        if Settings.ATTACH[key] or Settings.LEGACY_ATTACH[key] then
            map[Settings.AttachPath(key, "attach")] = true
            map[Settings.AttachPath(key, "attachX")] = 0
            map[Settings.AttachPath(key, "attachY")] = 0
        end
        if Settings.HIDE_WHEN_SELF[key] then
            map[Settings.HideWhenSelfPath(key)] = true
        end
        local d = Settings.AURA_DEFAULTS[key]
        for _, style in ipairs(UF.STYLE_ORDER) do
            if Settings.COMBO_POINTS[key] then
                map[Text.StylePath(key, style, "comboPoints")] = true
            end
            local function set(value, ...) map[Text.StylePath(key, style, "auras", ...)] = value end
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
                local function hp(value, field) map[Text.StylePath(key, style, "health", field)] = value end
                hp(true, "incomingHeals")
                hp(true, "absorb")
                hp(true, "overAbsorbGlow")
                hp(true, "healAbsorb")
            end
            -- Vanilla's bar: UI-StatusBar in green. "default" is both, and on
            -- a Modern bar the client's own fill in its own green.
            local function bar(value, ...) map[Text.StylePath(key, style, "health", ...)] = value end
            bar("default", "texture")
            bar("default", "colorMode")
            bar({ 0, 1, 0, 1 }, "color")
            bar(false, "hideTextureOnly")
            -- The power bar the same way: "default" is the fill each style
            -- draws, in the power's own colour. The colour is the XML's
            -- mana blue until the player picks one.
            local function power(value, ...) map[Text.StylePath(key, style, "power", ...)] = value end
            power("default", "texture")
            power("default", "colorMode")
            power({ 0, 0, 1, 1 }, "color")
            power(false, "hidden")
            power(false, "hideTextureOnly")
            if Settings.SURFACE[key].cost then
                power(false, "hideCost")
            end
            -- The portrait as each style draws it: uncropped, shown, opaque.
            local function portrait(value, field) map[Text.StylePath(key, style, "portrait", field)] = value end
            portrait(100, "zoom")
            portrait(false, "hidden")
            portrait(100, "opacity")
            -- Full opacity in every state, and every piece shown.
            if Settings.STATE_OPACITY[key] then
                for _, name in pairs(addon.Opacity.Keys.InCombat) do
                    map[Text.StylePath(key, style, name)] = 100
                end
            end
            for _, field in ipairs(Settings.MISC_ORDER) do
                if Settings.MiscOffered(key, style, field) then
                    map[Text.StylePath(key, style, "misc", field)] = false
                end
            end
            if Settings.SURFACE[key].barText then
                -- The current value at all times and no percent, which is what
                -- the frames showed before these settings. Vanilla's own, the
                -- Classic style's, is the statusText CVar off: "current / max"
                -- on mouseover. No face, size or style stored reads
                -- TextStatusBarText as it is.
                local classic = style == "classic"
                for _, barKey in ipairs(Settings.TEXT_BARS) do
                    local function text(value, slot, field)
                        map[Text.StylePath(key, style, barKey, "text", slot, field)] = value
                    end
                    text(classic and "hover" or "always", "value", "show")
                    text("never", "percent", "show")
                    text(classic and "currentMax" or "current", "value", "format")
                    -- Whole numbers on every style under the Camelot start,
                    -- the owner's call of 11 November 2026: on Classic
                    -- numbers the hundreds matter. The presets abbreviate
                    -- as Blizzard does (capNumericDisplay), in the stock below.
                    text("full", "value", "numberFormat")
                    for _, slot in ipairs(Settings.BAR_TEXT_SLOTS) do
                        text("default", slot, "colorMode")
                        text({ 1, 1, 1, 1 }, slot, "color")
                        text(0, slot, "offsetX")
                        text(0, slot, "offsetY")
                    end
                end
            end
        end
    end
    DB.RegisterDefaults(map)

    -- Each preset start draws its own style: Modern the client's frame,
    -- Classic the Camelot frame with Blizzard's values.
    for _, preset in ipairs(DB.PRESETS) do
        local styles = {}
        for _, key in ipairs(UF.ORDER) do
            styles[Text.StylePath(key, "camelot", "style")] = preset
        end
        DB.RegisterPreset(preset, styles)
    end

    -- Both presets put the target of target on Blizzard's own spot, read
    -- off the preset data at run time, so it does not hang off the target
    -- there. The legacy row keeps its stock value for the carry's read.
    local free = {}
    for key in pairs(Settings.ATTACH) do
        free[Settings.AttachPath(key, "attach")] = false
    end
    for key in pairs(Settings.LEGACY_ATTACH) do
        free[Settings.AttachPath(key, "attach")] = false
    end
    for _, key in ipairs(UF.ORDER) do
        if Settings.SURFACE[key].barText then
            for _, style in ipairs(UF.STYLE_ORDER) do
                for _, barKey in ipairs(Settings.TEXT_BARS) do
                    free[Text.StylePath(key, style, barKey, "text", "value", "numberFormat")] = "abbreviated"
                end
            end
        end
    end
    DB.RegisterStock(free)
end

--------------------------------------------------------------------------------
-- Scale and border style
--------------------------------------------------------------------------------
-- The frame-level rows at the top of each page. The scale is the frame's
-- whatever style it draws (text.lua, Text.SHARED); frame.lua lands it where
-- the HUD is loaded, and on retail the page writes it and nothing reads it.
-- The border style is one value for all five frames and dresses the Camelot
-- style's border alone. It has no page row: the Classic style is Blizzard's
-- silver, so the Camelot style keeps its bronze, and the debug command is
-- the one write left.

UF.SCALE_MIN, UF.SCALE_MAX = 0.5, 2

function UF.GetScale(key)
    return tonumber(DB.Get("unitFrames." .. key .. ".scale")) or 1
end

--- The page's write, clamped to the slider's range.
function UF.SetScale(key, value)
    local n = math.max(UF.SCALE_MIN, math.min(UF.SCALE_MAX, tonumber(value) or 1))
    DB.Set("unitFrames." .. key .. ".scale", n)
    if UF.ApplyScale then UF.ApplyScale(key) end
    return true
end

-- art.lua's three looks (art.lua, "The border style").
Settings.BORDER_STYLES = {
    values = { tint = "Bronze Tint", bronze = "Bronze Art", stock = "Blizzard Silver" },
    order = { "tint", "bronze", "stock" },
}

function UF.GetBorderStyle()
    local style = DB.Get("unitFrames.borderStyle")
    return Settings.BORDER_STYLES.values[style] and style or "tint"
end

--- "stock", "tint" or "bronze": the debug command's write.
function UF.SetBorderStyle(style)
    if not Settings.BORDER_STYLES.values[style] then return false end
    DB.Set("unitFrames.borderStyle", style)
    if UF.ApplyBorders then UF.ApplyBorders() end
    return true
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

--- Re-apply one frame's bar textures and colors, health and power, or every
--- frame's. Hide Power Bar takes the power strings with it, so they follow.
function UF.RefreshBarStyle(key)
    local Values = UF.Values
    if not (Values and UF.Frames) then return end
    for k, inst in pairs(UF.Frames) do
        if key == nil or k == key then
            Values.ApplyHealthStyle(inst)
            Values.ApplyPowerStyle(inst)
            UF.Frame.PaintAll(inst)
        end
    end
end

--- Re-apply one frame's portrait zoom and alpha, or every frame's.
function UF.RefreshPortrait(key)
    local Values = UF.Values
    if not (Values and UF.Frames) then return end
    for k, inst in pairs(UF.Frames) do
        if key == nil or k == key then Values.ApplyPortraitStyle(inst) end
    end
end

--- Re-apply one frame's heal prediction and absorbs, or every frame's.
function UF.RefreshHealth(key)
    if not (UF.HealPrediction and UF.Frames) then return end
    for k, inst in pairs(UF.Frames) do
        if key == nil or k == key then UF.HealPrediction.Apply(inst) end
    end
end
