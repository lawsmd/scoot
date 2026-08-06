-- damagemetersY/columns.lua - Column format definitions and meter type mappings
local _, addon = ...
local DMY = addon.DamageMetersY

--------------------------------------------------------------------------------
-- Column Format Definitions
--------------------------------------------------------------------------------

-- Each format maps to one or two Enum.DamageMeterType values and display metadata.
-- For combo formats, 'primary' is the main value and 'secondary' is in parentheses.

DMY.COLUMN_FORMATS = {
    -- Damage
    damage   = { meterType = 0,  valueField = "totalAmount",     headerText = "Damage" },
    dps      = { meterType = 1,  valueField = "amountPerSecond",  headerText = "DPS" },
    dmg_dps  = { primary = 0, secondary = 1, primaryField = "totalAmount", secondaryField = "amountPerSecond", headerText = "Damage (DPS)" },
    dps_dmg  = { primary = 1, secondary = 0, primaryField = "amountPerSecond", secondaryField = "totalAmount", headerText = "DPS (Damage)" },

    -- Healing
    healing  = { meterType = 2,  valueField = "totalAmount",     headerText = "Healing" },
    hps      = { meterType = 3,  valueField = "amountPerSecond",  headerText = "HPS" },
    heal_hps = { primary = 2, secondary = 3, primaryField = "totalAmount", secondaryField = "amountPerSecond", headerText = "Healing (HPS)" },
    hps_heal = { primary = 3, secondary = 2, primaryField = "amountPerSecond", secondaryField = "totalAmount", headerText = "HPS (Healing)" },

    -- Other
    absorbs   = { meterType = 4,  valueField = "totalAmount",  headerText = "Absorbs" },
    interrupts = { meterType = 5, valueField = "totalAmount",  headerText = "Interrupts" },
    dispels   = { meterType = 6,  valueField = "totalAmount",  headerText = "Dispels" },
    dmgTaken  = { meterType = 7,  valueField = "totalAmount",  headerText = "Dmg Taken" },
    avoidable = { meterType = 8,  valueField = "totalAmount",  headerText = "Avoidable" },
    deaths    = { meterType = 9,  valueField = "totalAmount",  headerText = "Deaths",  isDeaths = true },
    enemyDmg  = { meterType = 10, valueField = "totalAmount",  headerText = "Enemy Dmg" },
}
table.freeze(DMY.COLUMN_FORMATS)

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
