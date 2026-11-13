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

-- Vendored libraries are not ours to lint; docs/ is the synced doc base, and
-- its Lua (dev tools, payloads) is not addon code
exclude_files = { "libs/", "docs/" }

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
    "GetCurrentKeyBoardFocus",
    "GetTime",
    "hooksecurefunc",
    "InCombatLockdown",
    "issecretvalue",
    "RegisterUnitWatch",
    "UnregisterUnitWatch",
    "RegisterStateDriver",
    "UnregisterStateDriver",
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
    "UnitPartialPower",
    "UnitPowerDisplayMod",
    "GetRuneCooldown",
    "GetPowerRegenForPowerType",
    "GetUnitSecondaryPowerInfo",
    "UnitGetTotalAbsorbs",
    "SetPortraitTexture",
    "IsResting",
    "GetLootMethod",
    "GetFileIDFromPath",
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
    -- The Classic target frame's state reads (forever/unitframes/target.lua,
    -- pet.lua). Each is screened for a secret before it decides anything.
    "UnitIsCorpse",
    "UnitCanAttack",
    "UnitPlayerControlled",
    "UnitIsTapDenied",
    "UnitSelectionColor",
    "UnitIsPVP",
    "UnitIsPVPFreeForAll",
    "GetCreatureDifficultyColor",
    "GetRaidTargetIndex",
    "SetRaidTargetIconTexture",
    "GetPetHappiness",
    -- The pet happiness face and its tooltip (forever/unitframes/pet.lua).
    "C_PetInfo",
    "HasPetUI",
    "GameTooltip_AddNormalLine",
    "GameTooltip_Hide",
    "GameTooltip_SetTitle",
    "GAINING_LOYALTY",
    "LOSING_LOYALTY",
    "NONE",
    "PET_DAMAGE_PERCENTAGE",
    "PET_DIET_TEMPLATE",
    "PET_FOOD_DELIMIT",
    -- The Modern player frame's state reads (forever/unitframes/modern/
    -- player.lua), screened the same way.
    "HasLFGRestrictions",
    "UnitGroupRolesAssignedEnum",
    "UnitIsMercenary",
    -- The Classic frames' dead, ghost and auto-attack art (values.lua,
    -- player.lua), screened the same way, and the unit tooltip (frame.lua).
    "UnitIsDead",
    "UnitIsGhost",
    "UnitIsFeignDeath",
    "IsCurrentSpell",
    "GameTooltip_SetDefaultAnchor",
    "UnitName",
    "RegionalUniqueNamesEnabled",
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
    -- The chrome gallery (forever/gallery.lua) reads these
    "NineSliceLayouts",
    "C_XMLUtil",
    "GameFontHighlight",
    "GetBuildInfo",
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

    -- Dynamic Layouts' friendly target probe (core/dynamiclayouts/resolver.lua)
    "UnitIsFriend",

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
    "GetRealZoneText",
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
-- legal here and nowhere else. The conventions gate (docs/tools/gate.mjs) catches
-- the _G form.
files["Scoot.lua"] = {
    globals = { "SLASH_SCOOTCDM1", "SlashCmdList" },
}
-- The registry binds the brand's own slash word for whichever addon loaded it,
-- so the one write lives here instead of once per entry file.
files["core/commands.lua"] = {
    globals = { "SlashCmdList" },
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
-- Camelot's objective tracker (forever/objectivetracker/). mixins.lua owns
-- the three globals frames.xml names in mixin= attributes; the Blizzard
-- tracker names each file reads are declared where they are read.
files["forever/objectivetracker/mixins.lua"] = {
    globals = { "CamelotObjectiveTrackerMixin", "CamelotQuestItemSlotMixin", "CamelotQuestItemButtonMixin" },
    read_globals = {
        "ObjectiveTrackerContainerMixin",
        "GetQuestLogSpecialItemInfo", "IsQuestLogSpecialItemInRange", "GetQuestLogSpecialItemCooldown",
        "SetItemButtonTexture", "SetItemButtonCount", "SetItemButtonTextureVertexColor",
        "TOOLTIP_UPDATE_TIME",
    },
}
files["forever/objectivetracker/style.lua"] = {
    read_globals = {
        "CamelotObjectiveTracker", "ObjectiveTrackerManager", "ObjectiveTrackerFrame",
        "ObjectiveTrackerLineFont", "ScenarioObjectiveTracker",
    },
}
files["forever/objectivetracker/tracker.lua"] = {
    -- The containers are Camelot's own frames and tracker.lua writes two of
    -- their fields (editModeHeight, editModeName), so they are globals, not reads.
    globals = { "CamelotObjectiveTracker", "CamelotCurrentObjectiveTracker" },
    read_globals = {
        "ObjectiveTrackerManager", "ObjectiveTrackerFrame", "QuestObjectiveTracker",
        "CamelotQuestObjectiveTracker", "CamelotCampaignQuestObjectiveTracker",
        "CamelotCurrentQuestObjectiveTracker", "ObjectiveTrackerLineFont",
    },
}
files["forever/objectivetracker/itembutton.lua"] = {
    read_globals = { "GetQuestLogSpecialItemInfo" },
}
files["forever/objectivetracker/current.lua"] = {
    -- current.lua writes ShouldDisplayQuest on the three quest module instances.
    globals = {
        "CamelotQuestObjectiveTracker", "CamelotCampaignQuestObjectiveTracker",
        "CamelotCurrentQuestObjectiveTracker",
    },
    read_globals = { "QuestObjectiveTrackerMixin", "CampaignQuestObjectiveTrackerMixin", "C_SuperTrack" },
}
files["forever/objectivetracker/quests.lua"] = {
    -- What Blizzard's QuestMixin and the quest module's header click read,
    -- transcribed here so the Camelot modules stay off QuestCache and never
    -- show the world map.
    read_globals = {
        "QuestUtils_GetQuestName", "HaveQuestData", "C_QuestInfoSystem", "C_CampaignInfo",
        "IsModifiedClick", "ChatFrameUtil", "ShowQuestComplete", "C_SuperTrack", "QuestUtil",
        "MenuUtil", "InputUtil", "GamepadHudMode", "GamepadMode", "GetQuestLink",
        "QuestMapQuestOptions_AbandonQuest",
        "SUPER_TRACK_QUEST", "STOP_SUPER_TRACK_QUEST", "OBJECTIVES_HIDE_VIEW_IN_QUESTLOG",
        "OBJECTIVES_VIEW_IN_QUESTLOG", "OBJECTIVES_STOP_TRACKING", "SHARE_QUEST", "SHARE_IN_CHAT",
        "ABANDON_QUEST_ABBREV",
    },
}
-- Camelot's group finder (forever/groupfinder/): the listing API, the
-- Blizzard frames and templates the window names, and the util globals
-- Blizzard's own finder reads. The key is a path prefix.
files["forever/groupfinder/"] = {
    read_globals = {
        "C_LFGList", "C_LFGListRoles", "C_LFGInfo", "C_RaidLocks", "C_Discord", "C_VoiceChat",
        "LE_PARTY_CATEGORY_HOME", "UnitIsGroupLeader", "UnitIsGroupAssistant", "UnitGetAvailableRoles",
        "UnitSetRole", "InitiateRolePoll", "GetNumSavedInstances", "GetSavedInstanceInfo", "RequestRaidInfo",
        "strcmputf8i", "GetGeneralPlaystyleString", "GetTexCoordsForRole", "GetBackgroundTexCoordsForRole",
        "GroupFinderVanillaStyle_LoadUI", "LFGParentFrame", "LFGListingFrame", "LFGListingComment",
        "LFGBrowseFrame",
        "CreateScrollBoxListTreeListView", "CreateTreeDataProvider", "ScrollUtil", "CreateAnchor",
        "UISpecialFrames", "UIErrorsFrame", "StaticPopup_Show", "GameTooltip_Hide",
        "LFGActivityHeader", "LFGActivityEntry", "LFGActivityEntryTrivial", "LFGActivityEntryDifficult",
        "DISABLED_FONT_COLOR", "HIGHLIGHT_FONT_COLOR", "RED_FONT_COLOR",
        "LFG_TITLE", "LFG_LIST_TAB_1", "LFG_LIST_TAB_2", "LFG_LIST_TAB_3", "LFG_LIST_EDIT",
        "LFG_POST_GROUP_SOLO", "LFG_POST_GROUP_PARTY", "LFG_POST_GROUP_UPDATE", "LFG_LIST_UNLIST", "BACK",
        "LFG_LIST_ONLY_LEADER_CREATE", "LFG_LIST_ONLY_LEADER_UPDATE", "LFG_LIST_TOO_MANY_ACTIVITIES_SELECTED",
        "LFG_LIST_TOO_MANY_FOR_ACTIVITY", "GROUP_FINDER_PLAYSTYLE_REQUIRED", "DESCRIPTION_OF_YOUR_GROUP",
        "DESCRIPTION_OF_YOUR_GROUP_MANDATORY", "LFG_AUTHENTICATOR_DESCRIPTION_BOX",
        "LFG_LIST_IGNORE_SUGGESTED_LEVEL", "LFD_LEVEL_FORMAT_SINGLE", "LFD_LEVEL_FORMAT_RANGE", "BOSSES_KILLED",
        "LFG_LIST_MY_ACTIVITY_LIST_HEADER", "LFG_LIST_INDENT", "LFGBROWSE_ACTIVITY_COUNT",
        "CLASS_ROLE_NOT_RECOMMENDED", "ROLE_POLL", "ERR_LFG_ROLE_CHECK_ONLY_LEADER", "SELECT_YOUR_ROLE",
        "TANK", "HEALER", "DAMAGER", "LFG_LIST_NEW_PLAYER_FRIENDLY_TOOLTIP", "VOICE_CHAT",
        "VOICE_CHAT_MODE_NONE", "VOICE_CHAT_MODE_LEGACY", "VOICE_CHAT_MODE_DISCORD", "VOICE_CHAT_MODE_CUSTOM",
        "ERR_NOT_IN_COMBAT", "ERR_LFG_NO_LFG_OBJECT",
        -- The Browse tab
        "C_PartyInfo", "ChatFrameUtil", "GetGroupMemberCounts", "CreateFramePool", "CreateFontStringPool",
        "TreeDataProviderConstants", "ScrollBoxConstants",
        "LFGVANILLA_SETTING_BROWSE_SHOW_COLLAPSIBLE_CATEGORIES",
        "LFGBrowseGroupDataDisplay_Update", "LFGBrowseSearchEntryTooltip_UpdateAndShow",
        "LFGBrowseUtil_ReportListing", "LFGBrowseUtil_ReportAdvertisement",
        "GRAY_FONT_COLOR", "BRIGHTBLUE_FONT_COLOR", "LIGHTGREEN_FONT_COLOR",
        "LFG_LIST_CATEGORY_SOLO_PLAYERS", "LFG_LIST_CATEGORY_GROUPS", "LFG_LIST_SEARCH_FAILED",
        "LFG_LIST_NO_RESULTS_FOUND", "LFG_SELF_LISTING", "LFGBROWSE_ACTIVITY_MATCHING_COUNT", "LEVEL_ABBR",
        "CATEGORY", "LFG_TYPE_NONE", "LFGBROWSE_ACTIVITY_HEADER_DEFAULT", "LFGBROWSE_ACTIVITY_HEADER",
        "LFG_LIST_SEARCH_AGAIN", "SEARCHING", "SEND_MESSAGE", "GROUP_INVITE", "LFG_LIST_REPORT_GROUP_FOR",
        "REPORT_GROUP_FINDER_ADVERTISEMENT", "LFG_LIST_ENTRY_DELISTED", "LFG_LIST_NEW_PLAYER_FRIENDLY_HEADER",
        "LFG_LIST_BOSSES_DEFEATED",
    },
}
-- Camelot's action bars (forever/actionbars/). mixins.lua owns the two
-- globals frames.xml names in mixin= attributes; the Blizzard action bar
-- names each file reads are declared where they are read.
files["forever/actionbars/mixins.lua"] = {
    globals = { "CamelotActionBarMixin", "CamelotActionButtonMixin" },
    read_globals = {
        "BaseActionButtonMixin", "ActionBarActionButtonMixin", "ActionBarMixin",
        "QuickKeybindButtonTemplateMixin", "ActionButton_UpdateCooldownNumberHidden",
        "ClearActionButtonCooldowns", "ClearNewActionHighlight", "C_ActionBar",
        "RANGE_INDICATOR", "ACTIONBAR_HOTKEY_FONT_COLOR",
    },
}
files["forever/actionbars/text.lua"] = {
    read_globals = { "ACTIONBAR_HOTKEY_FONT_COLOR", "RED_FONT_COLOR" },
}
files["forever/actionbars/paging.lua"] = {
    read_globals = {
        "C_ActionBar", "MainActionBar", "RegisterAttributeDriver", "SecureCmdOptionParse",
        "NUM_ACTIONBAR_PAGES", "IsStealthed",
    },
}
files["forever/actionbars/clusters.lua"] = {
    read_globals = { "ACTION_BUTTON_SHOW_GRID_REASON_CVAR", "CamelotActionBarsParked" },
}
files["forever/actionbars/compact.lua"] = {
    read_globals = {
        "ActionBarMixin", "C_ActionBar", "bit", "NUM_ACTIONBAR_BUTTONS",
        "ACTION_BUTTON_SHOW_GRID_REASON_EVENT", "ACTION_BUTTON_SHOW_GRID_REASON_SPELLCOLLECTION",
        "KeybindFrames_InQuickKeybindMode", "InputUtil",
        "MultiActionBar_ShowAllGrids", "MultiActionBar_HideAllGrids",
    },
}
files["forever/gamepad.lua"] = {
    read_globals = { "InputUtil", "GamepadMode", "GamepadSharedUtility", "GamepadMainActionBarFrame",
        "issecurevariable" },
}
files["forever/actionbars/suppression.lua"] = {
    read_globals = { "MainActionBar" },
}
files["forever/actionbars/micro.lua"] = {
    read_globals = {
        "CharacterMicroButton", "GuildMicroButton", "MainMenuMicroButton", "MicroMenu",
        "GetFileStreamingStatus", "GetBackgroundLoadingStatus", "MainMenuBarPerformanceBarFrame_OnEnter",
        "GameTooltip_SetTitle", "FEATURE_NOT_AVAILBLE_PANDAREN", "FEATURE_BECOMES_AVAILABLE_AT_LEVEL",
        "GetValueOrCallFunction", "RED_FONT_COLOR", "MainMenuMicroButton_AreAlertsEnabled",
        "UIFrameFlash", "UIFrameFlashStop",
    },
}
files["forever/actionbars/bagbar.lua"] = {
    read_globals = {
        "GetInventorySlotInfo", "C_ActionBar", "GetInventoryItemTexture", "GetBindingText",
        "GameTooltip_SetTitle", "BACKPACK_TOOLTIP", "NUM_FREE_SLOTS", "KEYRING", "HIGHLIGHT_FONT_COLOR",
        "ContainerFrame_IsReagentBag", "EQUIP_CONTAINER_REAGENT", "EQUIP_CONTAINER", "PickupBagFromSlot",
        "PutItemInBackpack", "CursorHasItem", "PutKeyInKeyRing", "PutItemInBag",
    },
}
files["forever/actionbars/events.lua"] = {
    read_globals = { "C_ActionBar" },
}
files["forever/actionbars/bars.lua"] = {
    read_globals = { "C_ActionBar", "issecurevariable" },
}
files["forever/actionbars/stance.lua"] = {
    read_globals = {
        "GetShapeshiftFormInfo", "GetNumShapeshiftForms", "BaseActionButtonMixin", "GameTooltip_Hide",
    },
}
-- The gamepad bar replica (docs/actionbars/gamepadbar.md). gamepadmixins.lua
-- owns the globals gamepadframes.xml names in its mixin= attributes and
-- reads Blizzard_GamepadActionBars' mixins and utilities; gamepad.lua reads
-- Blizzard's gamepad frame and the keys.
files["forever/actionbars/gamepadmixins.lua"] = {
    globals = {
        "CamelotGamepadButtonMixin", "CamelotGamepadClickMixin", "CamelotGamepadBarMixin",
        "CamelotGamepadPageUnitMixin", "CamelotGamepadInputIconMixin", "CamelotGamepadInputPairMixin",
    },
    read_globals = {
        "CamelotActionButtonMixin", "GamepadActionBarButtonMixin", "GamepadActionBarButtonFlyoutMixin",
        "GamepadActionBarMixin", "GamepadActionBarBindingUtil", "GamepadActionBarStyleUtil",
        "ActionBarActionButtonMixin", "ClearActionButtonCooldowns",
        "C_ActionBar", "InputIconTextureSetUtility", "InputDeviceIconVariant",
    },
}
files["forever/actionbars/gamepad.lua"] = {
    read_globals = {
        "GamepadMainActionBarFrame", "C_GamepadUI", "IsKeyDown", "InputUtil",
        "InputDeviceIconSetManager", "issecurevariable",
    },
}
files["core/debug/taintscan.lua"] = {
    read_globals = { "issecurevariable", "canaccesstable" },
}
-- The Weapon Buff reminder's read: the item in each weapon slot and its icon.
files["core/components/scootauras/weaponbuff.lua"] = {
    read_globals = { "GetInventoryItemID", "GetInventoryItemTexture", "INVSLOT_MAINHAND", "INVSLOT_OFFHAND" },
}
-- The reminder's click target: its debug line reports whether a held item waits
-- for a weapon.
files["core/components/scootauras/missingcast.lua"] = {
    read_globals = { "SpellCanTargetItem" },
}
-- The Personal Resource Display (forever/personalresourcedisplay/). mixins.lua
-- owns the one global frames.xml names in a mixin= attribute; the other
-- files reach the frame through _G by name.
files["forever/personalresourcedisplay/mixins.lua"] = {
    globals = { "CamelotPersonalResourceDisplayMixin" },
}
-- The status bars (forever/statusbars/). mixins.lua owns the two globals
-- frames.xml names and reads Blizzard_StatusTrackingBar's; display.lua reads
-- the client's frames and constants.
files["forever/statusbars/mixins.lua"] = {
    globals = { "CamelotStatusTrackingManagerMixin", "CamelotStatusTrackingContainerMixin" },
    read_globals = { "StatusTrackingManagerMixin", "StatusTrackingBarContainerMixin", "StatusTrackingBarInfo" },
}
files["forever/statusbars/display.lua"] = {
    read_globals = {
        "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
        "StatusTrackingBarInfo", "CamelotStatusTrackingBarManager",
    },
}
-- The Group Finder (core/components/groupfinder/, ui/v2/groupfinder/): the
-- Premade Groups API, Blizzard's frames the host stands on, and the handler
-- and util functions the window's buttons run. Scoot-only files; the keys are
-- path prefixes.
files["core/components/groupfinder/"] = {
    read_globals = {
        "C_LFGList", "C_InstanceLeaver", "GetSpecializationRoleEnum",
        "GroupHasOfflineMember", "LE_PARTY_CATEGORY_HOME", "MAX_PARTY_MEMBERS",
        "LFGListUtil_GetActiveQueueMessage", "LFGListUtil_IsAppEmpowered", "LFGListUtil_IsEntryEmpowered",
        "PVEFrame", "PVEFrame_ShowFrame", "LFGListApplicationDialog", "LFGListInviteDialog", "LFGListFrame",
        "C_SocialRestrictions", "UnitIsGroupLeader", "bit",
        -- The saved searches' summary and the dungeon groups it reads
        "LFGListUtil_GetDecoratedCategoryName", "PlayerUtil", "PlayerIsTimerunning",
    },
}
files["ui/v2/groupfinder/"] = {
    read_globals = {
        "C_LFGList", "C_LFGInfo", "C_SocialRestrictions", "IsRestrictedAccount", "bit",
        "GetLFGRoles", "SetLFGRoles", "GameRulesUtil", "PlayerUtil", "ChatFrameUtil", "SecondsToTime",
        "PlayerIsTimerunning", "LOCALIZED_CLASS_NAMES_MALE",
        -- A saved search's paste: the key the copy waits for
        "IsMacClient", "IsMetaKeyDown",
        "LFGListFrame", "LFGListApplicationDialog",
        "LFGListUtil_GetDecoratedCategoryName", "LFGListUtil_IsAppEmpowered",
        "LFGListUtil_SortActivitiesByRelevancy", "LFGListCanChangeLanguages",
        "LFGListCategorySelection_SelectCategory", "LFGListCategorySelection_StartFindGroup",
        "LFGListSearchPanel_DoSearch", "LFGListSearchPanel_Clear", "LFGListSearchPanel_SetCategory",
        "LFGListFrame_SetActivePanel",
        "LFGList_ReportListing", "LFGList_ReportAdvertisement",
        -- The listing panel: Blizzard's creation panel's own steps and the
        -- reads behind its valid state
        "LFGListEntryCreation_SetBaseFilters", "LFGListEntryCreation_Clear", "LFGListEntryCreation_SetEditMode",
        "LFGListEntryCreation_Select", "LFGListEntryCreation_OnPlayStyleSelectedInternal",
        "LFGListEntryCreation_ClearFocus", "LFGListEntryCreationCancelButton_OnClick",
        "LFGListUtil_GetActiveQueueMessage", "MAX_LFG_LIST_GROUP_DROPDOWN_ENTRIES",
        "C_InstanceLeaver", "UnitFactionGroup", "LE_PARTY_CATEGORY_HOME", "GetAverageItemLevel", "GetNumGroupMembers",
        -- The viewer: the applicant actions, the party's own reads, Blizzard's
        -- convert-to-raid popup and its Browse handler
        "LFGApplicationBrowseGroupsButtonMixin", "LFGList_ReportApplicant", "LFGListUtil_GetQuestDescription",
        "GetGroupMemberCountsForDisplay", "C_ChallengeMode", "C_FriendList", "StaticPopup_Show",
        "MAX_PARTY_MEMBERS", "MAX_RAID_MEMBERS", "Ambiguate", "IsInRaid", "IsInGroup", "IsRestrictedAccount",
        "UnitIsGroupLeader", "UnitIsGroupAssistant", "UnitClass", "UnitGroupRolesAssigned", "UnitExists",
        "GetSpecialization", "GetSpecializationInfo",
        -- The invite dialog: Blizzard's own, parked, and its three handlers
        "LFGListInviteDialog", "LFGListInviteDialog_Accept", "LFGListInviteDialog_Decline",
        "LFGListInviteDialog_Acknowledge", "GroupHasOfflineMember",
        -- The search-entry tooltip, Blizzard's builder ported line for line
        "LFGListSearchEntryUtil_GetFriendList", "FACTION_STRINGS", "PLAYER_FACTION_GROUP", "PVPUtil",
        "CreateAtlasMarkup", "GameTooltip_AddHighlightLine", "GameTooltip_AddColoredLine",
        "GameTooltip_AddNormalLine", "GameTooltip_AddBlankLineToTooltip", "GameTooltip_AddErrorLine",
        "RED_FONT_COLOR", "GREEN_FONT_COLOR", "HIGHLIGHT_FONT_COLOR", "LIGHTBLUE_FONT_COLOR",
        "LFG_LIST_COMMENT_FONT_COLOR",
    },
}

-- Camelot's quality of life (forever/qualityoflife/): the Blizzard frame the
-- display file moves.
files["forever/qualityoflife/messagesdisplay.lua"] = {
    read_globals = { "UIErrorsFrame" },
}

-- Camelot's professions (forever/professions/): the two calls the client's
-- own professions book reads the player's professions with.
files["forever/professions/data.lua"] = {
    read_globals = { "GetProfessions", "GetProfessionInfo" },
}
-- The tracker's icon click opens and closes a profession's window.
files["forever/professions/tracker.lua"] = {
    read_globals = { "C_TradeSkillUI", "ProfessionsFrame" },
}

-- Keybind export and import (core/keybinds.lua, both TOCs): the binding
-- enumeration and writes.
files["core/keybinds.lua"] = {
    read_globals = {
        "GetNumBindings", "GetBinding", "SetBinding", "SaveBindings",
        "GetCurrentBindingSet", "GetBindingAction", "C_KeyBindings",
        "LoadBindings", "GetConvertedKeyOrButton", "IsKeyPressIgnoredForBinding",
        "CreateKeyChordStringUsingMetaKeyState",
    },
}
files["forever/actionbars/keybindmode.lua"] = {
    read_globals = {
        "GetBindingName", "GetBindingText", "GetBindingFromClick", "PetActionBar",
        "NOT_BOUND", "PRESS_KEY_TO_BIND", "ESCAPE_TO_UNBIND",
    },
}

-- The bag window (core/components/bags/, both TOCs): Blizzard's container
-- open state, the item button painters, the delete dialogs, the tooltip scan.
local BAGS_READ_GLOBALS = {
    "C_ActionBar", "ContainerFrameCombinedBags", "IsAnyBagOpen", "IsBagOpen", "CloseAllBags",
    "IsAnyStandardHeldBagOpen",
    "BAG_CLEANUP_BAGS", "SEARCH", "GetMoney", "GetMoneyString", "NUM_FREE_SLOTS",
    "SetItemButtonTexture", "SetItemButtonQuality", "SetItemButtonCount", "SetItemButtonDesaturated",
    "GetInventoryItemTexture", "StaticPopupDialogs", "CursorHasItem", "DeleteCursorItem",
    "C_TooltipInfo", "LOCKED",
    "KEYRING_CONTAINER", "GetKeyRingSize", "CloseBag", "KEYRING", "ButtonFrameTemplate_HidePortrait",
    "DELETE", "GameTooltip_AddErrorLine",
    "COMBINED_BAG_TITLE", "BAG_CLEANUP_BAGS_DESCRIPTION", "SETTINGS", "HIGHLIGHT_FONT_COLOR",
    "ClearItemButtonOverlay", "EMPTY_BAG_SLOT_EFFECT_COLOR", "MenuResponse",
    "BAG_NAME_BACKPACK", "BAG_NAME_BAG_1", "BAG_NAME_BAG_2", "BAG_NAME_BAG_3", "BAG_NAME_BAG_4",
    "ContainerFrame_CanContainerUseFilterMenu", "ContainerFrameUtil_EnumerateBagGearFilters",
    "BAG_FILTER_LABELS", "BAG_FILTER_ASSIGN_TO", "BAG_FILTER_IGNORE", "BAG_FILTER_CLEANUP",
    "BAG_FILTER_TITLE_SORTING", "SELL_ALL_JUNK_ITEMS_EXCLUDE_FLAG",
}
for _, name in ipairs({ "core", "window", "cells", "layout", "keyring", "menu", "delete", "picklock" }) do
    files["core/components/bags/" .. name .. ".lua"] = { read_globals = BAGS_READ_GLOBALS }
end
