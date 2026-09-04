-- Luacheck configuration for Scoot addon
-- Enforces Lua 5.1 compatibility (WoW runtime)
--
-- read_globals lists every Blizzard global the addon reads, so a W113
-- ("accessing undefined variable") on any other name is a broken reference:
-- a local declared after its first use, a deleted helper, or a typo. Keep the
-- list current when a new API is adopted; do not silence W113 inline.
-- A global with one owning file is declared in that file's block at the end,
-- so a second reader anywhere else is a W113 too.

std = "lua51"
max_line_length = false

-- Vendored libraries are not ours to lint
exclude_files = { "libs/" }

-- Suppress unused variable warnings for common WoW patterns
unused_args = false
unused_secondaries = false

-- Globals the addon defines or mutates on purpose. Globals with one owning
-- file (the slash commands, the popup registry) are in the per-file blocks.
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

    -- Player class probe (core/catalogs.lua)
    "UnitClass",

    -- C_ namespaces read across the components (census 2026-09-03)
    "C_ChallengeMode",
    "C_Container",
    "C_Crypto",
    "C_DurationUtil",
    "C_EventUtils",
    "C_GameRules",
    "C_Item",
    "C_Map",
    "C_Minimap",
    "C_MythicPlus",
    "C_PetBattles",
    "C_PvP",
    "C_QuestLog",
    "C_RestrictedActions",
    "C_SpellBook",
    "C_SplashScreen",
    "C_StorePublic",

    -- Unit, spell, cast, and action queries
    "FindBaseSpellByID",
    "GetActionInfo",
    "GetBindingKey",
    "GetMacroSpell",
    "GetRaidRosterInfo",
    "GetShapeshiftFormID",
    "IsPlayerSpell",
    "IsSpellKnown",
    "UnitAffectingCombat",
    "UnitCastingDuration",
    "UnitCastingInfo",
    "UnitChannelDuration",
    "UnitChannelInfo",
    "UnitClassBase",
    "UnitEmpoweredStagePercentages",
    "UnitFactionGroup",
    "UnitGroupRolesAssigned",
    "UnitHasVehicleUI",
    "UnitInVehicle",
    "UnitIsGroupLeader",
    "UnitRace",
    "GetUnitName",

    -- Class and specialization catalogs
    "GetClassInfo",
    "GetNumClasses",
    "GetNumSpecializations",
    "GetNumSpecializationsForClassID",
    "GetSpecializationInfoForClassID",
    "GetSpecializationNameByID",

    -- CVars, client, realm, and session state
    "GetCVar",
    "GetCVarBool",
    "GetCVarDefault",
    "SetCVar",
    "GetCurrentRegion",
    "GetCurrentRegionName",
    "GetFramerate",
    "GetGameTime",
    "GetInstanceInfo",
    "GetLocale",
    "GetNetStats",
    "GetRealmName",
    "GetScreenHeight",
    "GetZonePVPInfo",
    "IsAddOnLoaded",
    "IsInGuild",
    "IsLoggedIn",
    "ReloadUI",
    "WOW_PROJECT_ID",
    "WOW_PROJECT_MAINLINE",
    "LE_PARTY_CATEGORY_INSTANCE",

    -- Input, cursor, and merchant/loot helpers (core/qol.lua)
    "IsControlKeyDown",
    "IsShiftKeyDown",
    "ClearCursor",
    "GetCursorInfo",
    "ResetCursor",
    "SetCursor",
    "CanMerchantRepair",
    "GetRepairAllCost",
    "RepairAllItems",
    "GetNumLootItems",
    "LootSlot",
    "SendChatMessage",

    -- FrameXML utilities and mixins
    "AbbreviateLargeNumbers",
    "BreakUpLargeNumbers",
    "AuraUtil",
    "Constants",
    "CopyTable",
    "CreateFont",
    "CreateMinimalSliderFormatter",
    "GenerateClosure",
    "Menu",
    "MenuUtil",
    "PixelUtil",
    "Round",
    "ScrollUtil",
    "tAppendAll",
    "tCompare",
    "DefaultTooltipMixin",
    "MinimalSliderWithSteppersMixin",
    "SidePanelTabButtonMixin",
    "TooltipDataProcessor",
    "UIDropDownMenu_SetSelectedValue",
    "UIDropDownMenu_SetText",
    "UIFrameFadeOut",
    "UIFrameFadeRemoveFrame",
    "CooldownFrame_Set",
    "CompactUnitFrame_SetUnit",
    "CompactUnitFrame_UpdateRoleIcon",
    "SecureHandlerSetFrameRef",
    "SecureUnitButton_OnLoad",
    "StaticPopup_Hide",
    "StaticPopup_Show",
    "HideUIPanel",
    "ShowUIPanel",
    "ShowMacroFrame",
    "ToggleHelpFrame",
    "EJ_GetInstanceInfo",
    "FormatUnreadMailTooltip",
    "GetLatestThreeSenders",
    "GetMinimapShape",
    "GetMinimapZoneText",
    "HasNewMail",

    -- Blizzard frames and managers
    "AccountStoreFrame",
    "AccountStoreUtil",
    "ActionButtonSpellAlertManager",
    "AddonCompartmentFrame",
    "AddonList",
    "ColorPickerFrame",
    "CooldownViewerSettings",
    "DamageMeter",
    "DEFAULT_CHAT_FRAME",
    "EditModePresetLayoutManager",
    "EditModeSettingDisplayInfoManager",
    "EditModeSystemSettingsDialog",
    "FocusFrameToT",
    "GameMenuFrame",
    "GameTimeFrame",
    "HybridMinimap",
    "ItemRefTooltip",
    "Minimap",
    "MinimapCluster",
    "MinimapCompassTexture",
    "MinimapZoneTextButton",
    "PersonalResourceDisplayFrame",
    "PlayerSpellsFrame",
    "QuestScrollFrame",
    "SettingsTooltip",
    "StoreMicroButton",
    "TargetFrameToT",
    "TimeManagerClockButton",
    "UISpecialFrames",
    "WorldMapFrame",

    -- Font objects and color constants
    "ChatFontNormal",
    "GameFontNormalSmall",
    "DISABLED_FONT_COLOR",
    "NORMAL_FONT_COLOR",
    "WHITE_FONT_COLOR",
    "TOOLTIP_DEFAULT_BACKGROUND_COLOR",

    -- Localized strings and enum-like constants
    "ACCEPT",
    "CANCEL",
    "CLOSE",
    "NO",
    "OKAY",
    "YES",
    "FAILED",
    "INTERRUPTED",
    "HAVE_MAIL",
    "HAVE_MAIL_FROM",
    "HUD_EDIT_MODE_INVALID_LAYOUT_NAME",
    "NUM_CHAT_WINDOWS",
    "RESET_TO_DEFAULT",
    "RUNE_STATE_READY",
    "DAMAGE_METER_ABSORBS",
    "DAMAGE_METER_AVOIDABLE_DAMAGE_TAKEN",
    "DAMAGE_METER_CATEGORY_ACTIONS",
    "DAMAGE_METER_CATEGORY_DAMAGE",
    "DAMAGE_METER_CATEGORY_HEALING",
    "DAMAGE_METER_DAMAGE_DONE",
    "DAMAGE_METER_DAMAGE_TAKEN",
    "DAMAGE_METER_DISPELS",
    "DAMAGE_METER_DPS",
    "DAMAGE_METER_HEALING_DONE",
    "DAMAGE_METER_HPS",
    "DAMAGE_METER_INTERRUPTS",
    "DAMAGE_METER_TYPE_DEATHS",
    "DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN",

    -- WoW Lua runtime extras
    "debugprofilestop",
    "geterrorhandler",
    "seterrorhandler",
    "issecurevalue",

    -- Standard Lua globals WoW provides
    "string", "table", "math", "pairs", "ipairs", "type", "tostring", "tonumber",
    "select", "unpack", "wipe", "tinsert", "tremove", "sort",
    "format", "strsplit", "strtrim", "strmatch", "strfind", "gsub",
    "strupper", "strlower", "strjoin", "strconcat",
    "floor", "ceil", "abs", "min", "max",
    "print", "error", "assert", "loadstring",
    "setmetatable", "getmetatable", "rawget", "rawset",
    "next", "date", "time", "debugstack",

    -- Settings panel integration
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

-- Globals with one legitimate site. Declared per file so a read or write
-- anywhere else is a W113 or W111, the same signal as a broken reference.
-- The color tables are read through _G today; the block keeps a bare read
-- legal here and nowhere else. The conventions gate (tools/gate.mjs) catches
-- the _G form.
files["Scoot.lua"] = {
    globals = { "SLASH_SCOOT1", "SLASH_SCOOTCDM1", "SLASH_SCOOTDMSHOW1", "SLASH_SCOOTDMRESET1", "SlashCmdList" },
}
files["core/dialogs.lua"] = {
    globals = { "StaticPopupDialogs" },
}
files["core/colors.lua"] = {
    read_globals = { "RAID_CLASS_COLORS", "CUSTOM_CLASS_COLORS", "PowerBarColor" },
}
files["core/editmode/subgrid.lua"] = {
    read_globals = { "CreateObjectPool" },
}
