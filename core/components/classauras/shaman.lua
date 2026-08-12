-- classauras/shaman.lua - Shaman class aura definitions
local addonName, addon = ...

local CA = addon.ClassAuras

CA.RegisterAuras("SHAMAN", {
    {
        id = "flameShock",
        label = "Flame Shock",
        auraSpellId = 188389,       -- Flame Shock debuff
        cdmSpellId = 470411,        -- CDM base spell ID (linked: 188389 Flame Shock, override: 470057 Voltaic Blaze)
        cdmBorrow = true,
        engineDriven = true,        -- 12.1 AuraContainer slot engine (engine.lua)
        unit = "target",
        filter = "HARMFUL|PLAYER",
        enableLabel = "Enable Flame Shock Duration Tracker",
        enableDescription = "Show your target's Flame Shock duration as a dedicated, customizable aura.",
        editModeName = "Flame Shock",
        defaultPosition = { point = "CENTER", x = 0, y = -200 },
        defaultBarColor = { 1.0, 0.5, 0.0, 1.0 },  -- orange
        -- Frost Shock (196840) matches the same engine slot via the include
        -- filters; with iconMode "default" the engine stamps its real icon and
        -- name. Per-variant colors would need a dedicated variant slot.
        linkedSpellIds = { 196840 },
        elements = {
            { type = "text",    key = "duration", source = "duration", baseSize = 24, justifyH = "RIGHT" },
            { type = "texture", key = "icon",     customPath = "Interface\\AddOns\\Scoot\\media\\classauras\\PixelFlame", defaultSize = { 32, 32 } },
            { type = "bar",     key = "durationBar", source = "duration", fillMode = "deplete", defaultSize = { 120, 12 } },
        },
        settings = CA.DefaultSettings({
            textColor = { 1.0, 0.5, 0.0, 1.0 },
            barForegroundTint = { 1.0, 0.5, 0.0, 1.0 },
        }),
    },
})
