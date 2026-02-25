-- classauras/mage.lua - Mage class aura definitions
local addonName, addon = ...

local CA = addon.ClassAuras

CA.RegisterAuras("MAGE", {
    {
        id = "freezing",
        label = "Freezing",
        auraSpellId = 1221389,
        cdmSpellId = 1246769,  -- Shatter passive (CDM tracks Freezing stacks under this ID)
        cdmBorrow = true,
        unit = "target",
        filter = "HARMFUL|PLAYER",
        editModeName = "Freezing",
        defaultPosition = { point = "CENTER", x = 0, y = -200 },
        elements = {
            { type = "text",    key = "stacks", source = "applications", baseSize = 24, justifyH = "RIGHT" },
            { type = "texture", key = "icon",   customPath = "Interface\\AddOns\\ScooterMod\\media\\classauras\\PixelSnowflake", defaultSize = { 32, 32 } },
        },
        settings = {
            enabled         = { type = "addon", default = false },
            scale           = { type = "addon", default = 100 },
            iconMode        = { type = "addon", default = "default" },
            textFont        = { type = "addon", default = "FRIZQT__" },
            textStyle       = { type = "addon", default = "OUTLINE" },
            textSize        = { type = "addon", default = 24 },
            textColor       = { type = "addon", default = { 0.68, 0.85, 1.0, 1.0 } },
            textPosition    = { type = "addon", default = "inside" },
            textOuterAnchor = { type = "addon", default = "RIGHT" },
            textInnerAnchor = { type = "addon", default = "CENTER" },
            hideFromCDM     = { type = "addon", default = true },
            textOffsetX     = { type = "addon", default = 0 },
            textOffsetY     = { type = "addon", default = 0 },
            iconShape       = { type = "addon", default = 0 },
            borderStyle     = { type = "addon", default = "none" },
            borderThickness = { type = "addon", default = 1 },
            borderInsetH    = { type = "addon", default = 0 },
            borderInsetV    = { type = "addon", default = 0 },
            borderTintEnable = { type = "addon", default = false },
            borderTintColor  = { type = "addon", default = { 1, 1, 1, 1 } },
        },
    },
})
