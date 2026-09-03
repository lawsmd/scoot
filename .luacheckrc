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
    "Ambiguate",
    "AnchorUtil",
    -- 12.1 AuraContainer enums: plain globals, deliberately not under Enum
    "AuraContainerSortDirection",
    "AuraContainerSortMethod",
    "C_CurveUtil",
    "C_EditMode",
    "C_Secrets",
    "C_SpellActivationOverlay",
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
    "IsInInstance",
    "LibStub",
    "pcall",
    "PlaySound",
    "SOUNDKIT",
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
    -- Plain in 12.1 (no SecretReturns): the group missing-buff scan gates on
    -- them before it reads an aura on a group member. The last two let an AI
    -- companion in a follower dungeon or a walk-in party count as a member.
    "UnitIsConnected",
    "UnitIsVisible",
    "UnitInPartyIsAI",
    "UnitTreatAsPlayerForDisplay",
    -- Plain too, and the range gate on that scan: UnitInRange above is
    -- SecretReturns and unusable, so distance stands in for it.
    "UnitDistanceSquared",
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
    "Mixin",
    -- 12.1 ping receivers: used VERBATIM on unit frames, never overridden
    "PingableType_UnitFrameMixin",
    "GameTooltip",
    "PlayerFrame",
    "TargetFrame",
    "FocusFrame",

    -- Edit Mode branding (ui/v2/editmode/)
    "EditModeManagerFrame",
    "EventRegistry",
    "GameFontNormal",
    "GetCursorPosition",
    "IsMouseButtonDown",
    "GetMouseFoci",
    "HUD_EDIT_MODE_RESET_POSITION",
    "NineSliceUtil",
    "WorldFrame",
    "securecallfunction",

    -- Blizzard addon APIs
    "C_AddOns",
    "C_ClassColor",
    "C_CooldownViewer",
    "C_Covenants",
    "C_CVar",
    "C_DamageMeter",
    "C_DeathRecap",
    "C_PaperDollInfo",
    "C_Spell",
    "C_SpecializationInfo",
    "C_Texture",
    "CreateColor",
    "GetClassAtlas",
    "RAID_CLASS_COLORS",
    "CUSTOM_CLASS_COLORS",
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
