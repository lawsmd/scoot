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
    "C_EditMode",
    "C_Secrets",
    "C_Timer",
    "C_UnitAuras",
    "CreateFrame",
    "GetTime",
    "hooksecurefunc",
    "InCombatLockdown",
    "issecretvalue",
    "IsInRaid",
    "IsInGroup",
    "LibStub",
    "pcall",
    "UIParent",
    "UnitGUID",
    "UnitHealth",
    "UnitHealthMax",
    "UnitInRange",
    "UnitName",

    -- WoW frame methods/mixins (accessed as globals in some patterns)
    "GameTooltip",
    "PlayerFrame",
    "TargetFrame",
    "FocusFrame",

    -- Edit Mode branding (ui/v2/editmode/)
    "EditModeManagerFrame",
    "EventRegistry",
    "GameFontNormal",
    "GetCursorPosition",
    "HUD_EDIT_MODE_RESET_POSITION",
    "NineSliceUtil",
    "securecallfunction",

    -- Blizzard addon APIs
    "C_AddOns",
    "C_ClassColor",
    "C_Covenants",
    "C_PaperDollInfo",
    "C_Spell",
    "C_SpecializationInfo",
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
