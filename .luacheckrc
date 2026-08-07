-- Luacheck configuration for Scoot addon
-- Enforces Lua 5.1 compatibility (WoW runtime)

std = "lua51"
max_line_length = false

-- Suppress unused variable warnings for common WoW patterns
unused_args = false
unused_secondaries = false

-- WoW global environment
globals = {
    -- Scoot addon
    "Scoot",
}

read_globals = {
    -- WoW core API
    "AbbreviateNumbers",
    "C_CurveUtil",
    "C_EditMode",
    "C_Secrets",
    "C_StringUtil",
    "C_Timer",
    "C_UnitAuras",
    "CreateAbbreviateConfig",
    "CreateFrame",
    "Enum",
    "GetTime",
    "hooksecurefunc",
    "InCombatLockdown",
    "issecretvalue",
    "RegisterUnitWatch",
    "UnregisterUnitWatch",
    "IsInRaid",
    "IsInGroup",
    "LibStub",
    "pcall",
    "UIParent",
    "UnitGUID",
    "UnitHealth",
    "UnitHealthMax",
    "UnitHealthPercent",
    "UnitPower",
    "UnitPowerMax",
    "UnitPowerPercent",
    "UnitPowerType",
    "GetUnitSecondaryPowerInfo",
    "UnitGetTotalAbsorbs",
    "CreateUnitHealPredictionCalculator",
    "UnitGetDetailedHealPrediction",
    "UnitExists",
    "UnitInRange",
    "UnitIsPlayer",
    -- Both plain reads in 12.0 (no SecretReturns in UnitDocumentation.lua):
    -- the dead skull and the elite/rare icon branch on them directly.
    "UnitIsDeadOrGhost",
    "UnitClassification",
    "UnitName",
    "UnitLevel",
    "UnitEffectiveLevel",
    "GameRulesUtil",
    "GetMaxPlayerLevel",
    "IsPlayerAtEffectiveMaxLevel",

    -- WoW frame methods/mixins (accessed as globals in some patterns)
    "BackdropTemplateMixin",
    "GameTooltip",
    "PlayerFrame",
    "TargetFrame",
    "FocusFrame",

    -- Edit Mode branding (ui/v2/editmode/)
    "EditModeManagerFrame",
    "EventRegistry",
    "GameFontNormal",
    "GetCursorPosition",
    "GetMouseFoci",
    "HUD_EDIT_MODE_RESET_POSITION",
    "NineSliceUtil",
    "WorldFrame",
    "securecallfunction",

    -- Blizzard addon APIs
    "C_AddOns",
    "C_ClassColor",
    "C_Covenants",
    "C_PaperDollInfo",
    "C_Spell",
    "C_SpecializationInfo",
    "C_Texture",
    "CreateColor",
    "GetSpecialization",
    "GetSpecializationInfo",

    -- Inspect service (core/inspect.lua)
    "CanInspect",
    "ClearInspectPlayer",
    "GetAverageItemLevel",
    "GetInspectSpecialization",
    "GetNumGroupMembers",
    "GetSpecializationInfoByID",
    "InspectFrame",
    "NotifyInspect",
    "UnitInParty",
    "UnitInRaid",
    "UnitIsUnit",
    "UnitTokenFromGUID",

    -- Standard Lua globals WoW provides
    "string", "table", "math", "pairs", "ipairs", "type", "tostring", "tonumber",
    "select", "unpack", "wipe", "tinsert", "tremove", "sort",
    "format", "strsplit", "strtrim", "strmatch", "strfind", "gsub",
    "strupper", "strlower", "strjoin", "strconcat",
    "floor", "ceil", "abs", "min", "max",
    "print", "error", "assert", "loadstring",
    "setmetatable", "getmetatable", "rawget", "rawset",
    "next", "date", "time", "debugstack",

    -- WoW event/frame scripting
    "SLASH_SCOOT1",
    "SLASH_SCOOT2",
    "SlashCmdList",
    "Settings",
    "SettingsPanel",
    "InterfaceOptions_AddCategory",
}

-- Ignore warnings about accessing undefined fields on self/frame objects
-- (WoW frames have dynamic methods not visible to static analysis)
ignore = {
    "212",  -- unused argument (common in WoW callbacks)
    "213",  -- unused loop variable
}
