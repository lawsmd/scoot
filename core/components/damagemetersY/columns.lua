-- damagemetersY/columns.lua - Column format definitions and meter type mappings
local _, addon = ...
local DMY = addon.DamageMetersY

--------------------------------------------------------------------------------
-- Column Format Definitions
--------------------------------------------------------------------------------

-- Each format maps to one or two Enum.DamageMeterType values and display metadata.
-- For combo formats, 'primary' is the main value and 'secondary' is in parentheses.

-- headerAbbrev: the Abbreviated column-header mode's label.
-- iconKind: the metric KIND for the Icons header mode — every format of one
-- kind (e.g. all four damage formats) shares a single DMY.HEADER_ICONS entry.
DMY.COLUMN_FORMATS = {
    -- Damage
    damage   = { meterType = 0,  valueField = "totalAmount",     headerText = "Damage", headerAbbrev = "Dmg", iconKind = "damage" },
    dps      = { meterType = 1,  valueField = "amountPerSecond",  headerText = "DPS", headerAbbrev = "DPS", iconKind = "damage" },
    dmg_dps  = { primary = 0, secondary = 1, primaryField = "totalAmount", secondaryField = "amountPerSecond", headerText = "Damage (DPS)", headerAbbrev = "Dmg(DPS)", iconKind = "damage" },
    dps_dmg  = { primary = 1, secondary = 0, primaryField = "amountPerSecond", secondaryField = "totalAmount", headerText = "DPS (Damage)", headerAbbrev = "DPS(Dmg)", iconKind = "damage" },

    -- Healing
    healing  = { meterType = 2,  valueField = "totalAmount",     headerText = "Healing", headerAbbrev = "Heal", iconKind = "healing" },
    hps      = { meterType = 3,  valueField = "amountPerSecond",  headerText = "HPS", headerAbbrev = "HPS", iconKind = "healing" },
    heal_hps = { primary = 2, secondary = 3, primaryField = "totalAmount", secondaryField = "amountPerSecond", headerText = "Healing (HPS)", headerAbbrev = "Heal(HPS)", iconKind = "healing" },
    hps_heal = { primary = 3, secondary = 2, primaryField = "amountPerSecond", secondaryField = "totalAmount", headerText = "HPS (Healing)", headerAbbrev = "HPS(Heal)", iconKind = "healing" },

    -- Other
    absorbs   = { meterType = 4,  valueField = "totalAmount",  headerText = "Absorbs", headerAbbrev = "Absrb", iconKind = "absorbs" },
    interrupts = { meterType = 5, valueField = "totalAmount",  headerText = "Interrupts", headerAbbrev = "Intrpts", iconKind = "interrupts" },
    dispels   = { meterType = 6,  valueField = "totalAmount",  headerText = "Dispels", headerAbbrev = "Dspls", iconKind = "dispels" },
    dmgTaken  = { meterType = 7,  valueField = "totalAmount",  headerText = "Dmg Taken", headerAbbrev = "DmgTkn", iconKind = "dmgTaken" },
    avoidable = { meterType = 8,  valueField = "totalAmount",  headerText = "Avoidable", headerAbbrev = "Avdble", iconKind = "avoidable" },
    deaths    = { meterType = 9,  valueField = "totalAmount",  headerText = "Deaths",  isDeaths = true, headerAbbrev = "Dead", iconKind = "deaths" },
    enemyDmg  = { meterType = 10, valueField = "totalAmount",  headerText = "Enemy Dmg", headerAbbrev = "EnmyDmg", iconKind = "enemyDmg" },
}
table.freeze(DMY.COLUMN_FORMATS)

--------------------------------------------------------------------------------
-- Header Icons (Icons column-header mode)
--------------------------------------------------------------------------------

-- One icon per metric KIND, rendered as a real Texture (never |T| markup —
-- markup cannot desaturate), tinted by the resolved Header Row color.
-- `scale` and `yOffset` are per-icon normalization tweaks so visually
-- different sources read as one matched set; tune them with the in-game
-- gallery: /scoot debug dmY headericons  (edit here, /reload, re-check).
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
        return 1 -- DPS fallback
    end
    local fmt = windowConfig.columns[1].format
    local def = DMY.COLUMN_FORMATS[fmt]
    if not def then return 1 end
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

--- Formats excluded from secondary (non-primary) columns.
--- Historical: the old per-GUID source API had no amountPerSecond. The
--- session-correlation path now reads full sources, so rate formats could
--- become legal secondaries later (future enhancement; kept excluded so
--- existing migrated configs stay stable).
DMY.SECONDARY_EXCLUDED_FORMATS = {
    dps      = true,
    hps      = true,
    dps_dmg  = true,
    hps_heal = true,
    dmg_dps  = true,
    heal_hps = true,
}
table.freeze(DMY.SECONDARY_EXCLUDED_FORMATS)

--- Migration map: excluded format → totalAmount equivalent for auto-migration.
DMY.SECONDARY_MIGRATION_MAP = {
    dps      = "damage",
    hps      = "healing",
    dps_dmg  = "damage",
    hps_heal = "healing",
    dmg_dps  = "damage",
    heal_hps = "healing",
}
table.freeze(DMY.SECONDARY_MIGRATION_MAP)
