-- damagemetersY/columns.lua - Column format definitions and meter type mappings
local _, addon = ...
local DMY = addon.DamageMetersY

--------------------------------------------------------------------------------
-- Column Format Definitions
--------------------------------------------------------------------------------

-- Each format maps to one or two Enum.DamageMeterType values (DMY.MT, read by
-- name in core.lua) and display metadata.
-- For combo formats, 'primary' is the main value and 'secondary' is in parentheses.

-- headerAbbrev: the Abbreviated column-header mode's label.
-- iconKind: the metric KIND for the Icons header mode — every format of one
-- kind (e.g. all four damage formats) shares a single DMY.HEADER_ICONS entry.
local MT = DMY.MT

local FORMATS = {
    -- Damage
    damage   = { meterType = MT.DamageDone,  valueField = "totalAmount",     headerText = "Damage", headerAbbrev = "Dmg", iconKind = "damage" },
    dps      = { meterType = MT.Dps,  valueField = "amountPerSecond",  headerText = "DPS", headerAbbrev = "DPS", iconKind = "damage" },
    dmg_dps  = { primary = MT.DamageDone, secondary = MT.Dps, primaryField = "totalAmount", secondaryField = "amountPerSecond", headerText = "Damage (DPS)", headerAbbrev = "Dmg(DPS)", iconKind = "damage" },
    dps_dmg  = { primary = MT.Dps, secondary = MT.DamageDone, primaryField = "amountPerSecond", secondaryField = "totalAmount", headerText = "DPS (Damage)", headerAbbrev = "DPS(Dmg)", iconKind = "damage" },

    -- Healing
    healing  = { meterType = MT.HealingDone,  valueField = "totalAmount",     headerText = "Healing", headerAbbrev = "Heal", iconKind = "healing" },
    hps      = { meterType = MT.Hps,  valueField = "amountPerSecond",  headerText = "HPS", headerAbbrev = "HPS", iconKind = "healing" },
    heal_hps = { primary = MT.HealingDone, secondary = MT.Hps, primaryField = "totalAmount", secondaryField = "amountPerSecond", headerText = "Healing (HPS)", headerAbbrev = "Heal(HPS)", iconKind = "healing" },
    hps_heal = { primary = MT.Hps, secondary = MT.HealingDone, primaryField = "amountPerSecond", secondaryField = "totalAmount", headerText = "HPS (Healing)", headerAbbrev = "HPS(Heal)", iconKind = "healing" },

    -- Other
    absorbs   = { meterType = MT.Absorbs,  valueField = "totalAmount",  headerText = "Absorbs", headerAbbrev = "Absrb", iconKind = "absorbs" },
    interrupts = { meterType = MT.Interrupts, valueField = "totalAmount",  headerText = "Interrupts", headerAbbrev = "Intrpts", iconKind = "interrupts" },
    dispels   = { meterType = MT.Dispels,  valueField = "totalAmount",  headerText = "Dispels", headerAbbrev = "Dspls", iconKind = "dispels" },
    dmgTaken  = { meterType = MT.DamageTaken,  valueField = "totalAmount",  headerText = "Dmg Taken", headerAbbrev = "DmgTkn", iconKind = "dmgTaken" },
    avoidable = { meterType = MT.AvoidableDamageTaken,  valueField = "totalAmount",  headerText = "Avoidable", headerAbbrev = "Avdble", iconKind = "avoidable" },
    deaths    = { meterType = MT.Deaths,  valueField = "totalAmount",  headerText = "Deaths",  isDeaths = true, headerAbbrev = "Dead", iconKind = "deaths" },
    enemyDmg  = { meterType = MT.EnemyDamageTaken, valueField = "totalAmount",  headerText = "Enemy Dmg", headerAbbrev = "EnmyDmg", iconKind = "enemyDmg" },
}

-- A format whose meter type the client's enum does not name is not offered:
-- the menus and the settings page list what is left in the table.
for key, def in pairs(FORMATS) do
    local missing
    if def.primaryField then
        missing = def.primary == nil or def.secondary == nil
    else
        missing = def.meterType == nil
    end
    if missing then FORMATS[key] = nil end
end

DMY.COLUMN_FORMATS = FORMATS
table.freeze(DMY.COLUMN_FORMATS)

--------------------------------------------------------------------------------
-- Meter families
--------------------------------------------------------------------------------

-- Two meter types are one family when a source record of either carries both
-- of their values: a DamageDone or a Dps record holds the damage total and the
-- damage rate, and a HealingDone or an Hps record the same for healing. A
-- column in the primary column's family therefore reads the row's own record
-- in combat and needs no identity match to find its player (layout.lua).
DMY.METER_FAMILY = {}
for family, names in pairs({
    damage = { "DamageDone", "Dps" },
    healing = { "HealingDone", "Hps" },
}) do
    for _, name in ipairs(names) do
        local mt = MT[name]
        if mt ~= nil then DMY.METER_FAMILY[mt] = family end
    end
end
table.freeze(DMY.METER_FAMILY)

--- True when two meter types are the same, or share a family.
function DMY._SameMeterFamily(a, b)
    if a == nil or b == nil then return false end
    if a == b then return true end
    local family = DMY.METER_FAMILY[a]
    return family ~= nil and family == DMY.METER_FAMILY[b]
end

--------------------------------------------------------------------------------
-- Header Icons (Icons column-header mode)
--------------------------------------------------------------------------------

-- One icon per metric KIND, rendered as a real Texture (never |T| markup —
-- markup cannot desaturate), tinted by the resolved Header Row color.
-- `scale` and `yOffset` are per-icon normalization tweaks so visually
-- different sources read as one matched set; tune them with the in-game
-- gallery, the debug command dmY headericons (edit here, /reload, re-check).
--
-- The damage/healing/dmgTaken trio comes from one Blizzard atlas family
-- (tiny role icons: sword / plus / shield); deaths is the raid-marker skull
-- (frameless white silhouette); avoidable is the ping-system warning "!"
-- glyph (tall and narrow — atlas icons keep their aspect ratio, see
-- DMY._HeaderIconDims). The rest are desaturated spell icons with a zoom
-- texCoord to crop their painterly borders.
local SPELL_ICON_ZOOM = { 0.08, 0.92, 0.08, 0.92 }

DMY.HEADER_ICONS = {
    damage     = { atlas = "roleicon-tiny-dps",    desaturate = true, scale = 1.0 },
    healing    = { atlas = "roleicon-tiny-healer", desaturate = true, scale = 1.0 },
    dmgTaken   = { atlas = "roleicon-tiny-tank",   desaturate = true, scale = 1.0 },
    -- GM-raidMarkerN atlases are numbered in REVERSE of raid-target indices
    -- (Blizzard's CRF manager maps them via ReverseMarkerID): 1 = skull, 8 = star
    deaths     = { atlas = "GM-raidMarker1",       desaturate = true, scale = 1.0 },
    avoidable  = { atlas = "Ping_Marker_Icon_Warning", desaturate = true, scale = 1.0 },
    interrupts = { texture = "Interface\\Icons\\Ability_Kick",               texCoord = SPELL_ICON_ZOOM, desaturate = true, scale = 1.0 },
    dispels    = { texture = "Interface\\Icons\\Spell_Holy_DispelMagic",     texCoord = SPELL_ICON_ZOOM, desaturate = true, scale = 1.0 },
    absorbs    = { texture = "Interface\\Icons\\Spell_Holy_PowerWordShield", texCoord = SPELL_ICON_ZOOM, desaturate = true, scale = 1.0 },
    enemyDmg   = { texture = "Interface\\Icons\\Ability_Hunter_SniperShot",  texCoord = SPELL_ICON_ZOOM, desaturate = true, scale = 1.0 },
}
table.freeze(DMY.HEADER_ICONS)

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Returns the primary Enum.DamageMeterType for a window's first column.
function DMY._GetPrimaryMeterType(windowConfig)
    if not windowConfig or not windowConfig.columns or #windowConfig.columns == 0 then
        return MT.Dps -- DPS fallback
    end
    local fmt = windowConfig.columns[1].format
    local def = DMY.COLUMN_FORMATS[fmt]
    if not def then return MT.Dps end
    return def.primary or def.meterType
end

--- Returns a set of all unique Enum.DamageMeterType values needed for a window's columns.
function DMY._GetNeededMeterTypes(columns)
    local needed = {}
    for _, col in ipairs(columns) do
        local def = DMY.COLUMN_FORMATS[col.format]
        if def then
            if def.primary then
                needed[def.primary] = true
                needed[def.secondary] = true
            else
                needed[def.meterType] = true
            end
        end
    end
    return needed
end

--- Returns the header text for a column format key.
function DMY._GetColumnHeader(formatKey)
    local def = DMY.COLUMN_FORMATS[formatKey]
    return def and def.headerText or "?"
end

--- Splits a dual-metric header label into two lines: the primary metric on top,
--- its parenthesised secondary underneath, so "DPS (Damage)" and its
--- abbreviated form "DPS(Dmg)" each break after the primary metric.
--- Returns nil when there is no trailing parenthesised part to move down.
function DMY._StackHeaderLabel(text)
    if type(text) ~= "string" then return nil end
    local head, paren = text:match("^(.-)%s*(%b())$")
    if not head or head == "" then return nil end
    return head .. "\n" .. paren
end
