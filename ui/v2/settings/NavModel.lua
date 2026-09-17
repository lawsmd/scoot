-- settings/NavModel.lua - Scoot's page tree for the settings panel.
--
-- ui/v2/Navigation.lua draws whatever this table holds and reads it only at
-- call time, so the tree lives with the product that owns the pages rather
-- than with the framework. Camelot supplies its own in forever/menu.lua.
-- Each child key names a renderer registered through
-- addon.UI.SettingsPanel:RegisterRenderer; a key with no renderer draws the
-- "not yet implemented" placeholder.
local addonName, addon = ...

local Navigation = addon.UI.Navigation

Navigation.NavModel = {
    -- "Features" and "Search" are now top-bar header buttons (settingspanel/core.lua),
    -- not NavModel entries. Their renderer keys ("startHere", "search") remain unchanged.
    {
        key = "profiles",
        label = "Profiles",
        collapsible = true,
        children = {
            { key = "profilesManage", label = "Manage Profiles" },
            { key = "profilesPresets", label = "Presets" },
            { key = "profilesRules", label = "Rules" },
            { key = "profilesImportExport", label = "Import/Export" },
        },
    },
    {
        key = "applyAll",
        label = "Apply All",
        collapsible = true,
        children = {
            { key = "applyAllFonts", label = "Font" },
            { key = "applyAllTextures", label = "Bar Texture" },
        },
    },
    {
        key = "interface",
        label = "Interface",
        collapsible = true,
        children = {
            { key = "damageMeter", label = "Damage Meters", module = "damageMeter", moduleSubId = "damageMeter",
                variant = "X",
                versionBadge = { label = "X", title = "Damage Meters X", text = "Reskins Blizzard's built-in damage meter frames while keeping the native functionality intact." } },
            { key = "damageMeterV2", label = "Damage Meters", module = "damageMeter", moduleSubId = "damageMeterV2",
                variant = "Y",
                versionBadge = { label = "Y", title = "Damage Meters Y", text = "Custom frames that replace Blizzard's meter entirely. Multi-column and multi-window support." } },
            { key = "tooltip", label = "Tooltip", module = "tooltip" },
            { key = "objectiveTracker", label = "Objective Tracker", module = "objectiveTracker" },
            { key = "minimap", label = "Minimap", module = "minimap" },
            { key = "chat", label = "Chat" },
            { key = "notes", label = "Notes", module = "notes" },
            { key = "misc", label = "Misc." },
        },
    },
    {
        key = "bossWarnings",
        label = "Boss Warnings",
        collapsible = true,
        children = {
            { key = "bwWarnings", label = "Boss Warnings", module = "bossWarnings" },
            { key = "bwTimeline", label = "Boss Timeline", module = "bossWarnings" },
            { key = "bwBars", label = "Boss Bars", module = "bossWarnings" },
        },
    },
    {
        key = "qol",
        label = "Quality of Life",
        collapsible = true,
        children = {
            { key = "qolEditMode", label = "Edit Mode" },
            { key = "qolLootVendors", label = "Loot & Vendors" },
            { key = "qolQuests", label = "Map & Quests" },
            { key = "qolDungeonJournal", label = "Dungeon Journal" },
            { key = "qolSmallFixes", label = "Small Fixes" },
        },
    },
    {
        key = "cdm",
        label = "Cooldown Manager",
        collapsible = true,
        children = {
            { key = "cdmQoL", label = "Quality of Life", module = "cooldownManager" },
            { key = "essentialCooldowns", label = "Essential Cooldowns", module = "cooldownManager" },
            { key = "utilityCooldowns", label = "Utility Cooldowns", module = "cooldownManager" },
            { key = "trackedBuffs", label = "Tracked Buffs", module = "cooldownManager" },
            { key = "trackedBars", label = "Tracked Bars", module = "cooldownManager" },
            { key = "customGroup1", label = "Custom Group 1", module = "cooldownManager" },
            { key = "customGroup2", label = "Custom Group 2", module = "cooldownManager" },
            { key = "customGroup3", label = "Custom Group 3", module = "cooldownManager" },
            { key = "customGroup4", label = "Custom Group 4", module = "cooldownManager" },
            { key = "customGroup5", label = "Custom Group 5", module = "cooldownManager" },
        },
    },
    {
        key = "scootAuras",
        label = "ScootAuras",
        collapsible = true,
        children = {
            { key = "scootAurasList", label = "Aura List", module = "scootAuras", betaBadge = true },
        },
    },
    {
        key = "prd",
        label = "Personal Resource",
        collapsible = true,
        children = {
            { key = "prdGeneral", label = "General", module = "prd" },
            { key = "prdHealthBar", label = "Health Bar", module = "prd" },
            { key = "prdPowerBar", label = "Power Bar", module = "prd" },
            -- Only Demon Hunter, Evoker, Monk, Priest and Druid have an alternate power bar
            -- (Devourer / Augmentation / Brewmaster / Shadow / Balance). The page renders
            -- fine for anyone (profiles are shared across characters); the nav hides it for
            -- classes that can never see the bar.
            { key = "prdAltPowerBar", label = "Alternate Power Bar", module = "prd",
              isVisible = function()
                  return addon.PRD and addon.PRD.PlayerClassHasAltPowerBar and addon.PRD.PlayerClassHasAltPowerBar()
              end },
            { key = "prdClassResource", label = "Class Resource", module = "prd" },
        },
    },
    {
        key = "unitFrames",
        label = "Unit Frames",
        collapsible = true,
        children = {
            -- Player and Target are three-state units (OFF / X / Z, cycled on
            -- the Features page), so each is a PAIR of children sharing a
            -- variantGroup: the group's active member is the only one shown.
            -- When the whole group is off, only the groupFallback member
            -- renders -- grayed, and with hideBadgesWhenDisabled its badge is
            -- suppressed so an OFF unit reads as plain "Player", not "Player
            -- [X]". The disabled hover tooltip already points at the Features
            -- page.
            { key = "ufPlayer", label = "Player", module = "unitFrames", moduleSubId = "Player",
                variant = "X",
                versionBadge = { label = "X", title = "Player Frame X", text = "Blizzard's own Player frame, restyled in place by Scoot." },
                variantGroup = "ufPlayer", groupFallback = true, hideBadgesWhenDisabled = true },
            { key = "ufzPlayer", label = "Player", module = "unitFramesZ", moduleSubId = "Player",
                variant = "Z",
                versionBadge = { label = "Z", title = "Player Frame Z", text = "Scoot's own text-first Player frame, replacing Blizzard's while enabled. Positioned in Edit Mode and configured here." },
                betaBadge = true,
                variantGroup = "ufPlayer" },
            { key = "ufTarget", label = "Target", module = "unitFrames", moduleSubId = "Target",
                variant = "X",
                versionBadge = { label = "X", title = "Target Frame X", text = "Blizzard's own Target frame, restyled in place by Scoot." },
                variantGroup = "ufTarget", groupFallback = true, hideBadgesWhenDisabled = true },
            { key = "ufzTarget", label = "Target", module = "unitFramesZ", moduleSubId = "Target",
                variant = "Z",
                versionBadge = { label = "Z", title = "Target Frame Z", text = "Scoot's own text-first Target frame, replacing Blizzard's while enabled. Positioned in Edit Mode and configured here." },
                betaBadge = true,
                variantGroup = "ufTarget" },
            { key = "ufFocus", label = "Focus", module = "unitFrames", moduleSubId = "Focus",
                variant = "X",
                versionBadge = { label = "X", title = "Focus Frame X", text = "Blizzard's own Focus frame, restyled in place by Scoot." },
                variantGroup = "ufFocus", groupFallback = true, hideBadgesWhenDisabled = true },
            { key = "ufzFocus", label = "Focus", module = "unitFramesZ", moduleSubId = "Focus",
                variant = "Z",
                versionBadge = { label = "Z", title = "Focus Frame Z", text = "Scoot's own text-first Focus frame, replacing Blizzard's while enabled. Positioned in Edit Mode and configured here." },
                betaBadge = true,
                variantGroup = "ufFocus" },
            { key = "ufPet", label = "Pet", module = "unitFrames", moduleSubId = "Pet" },
            { key = "ufToT", label = "Target of Target", module = "unitFrames", moduleSubId = "TargetOfTarget",
                variant = "X",
                versionBadge = { label = "X", title = "Target of Target X", text = "Blizzard's own Target of Target frame, restyled in place by Scoot." },
                variantGroup = "ufToT", groupFallback = true, hideBadgesWhenDisabled = true },
            { key = "ufzToT", label = "Target of Target", module = "unitFramesZ", moduleSubId = "TargetOfTarget",
                variant = "Z",
                versionBadge = { label = "Z", title = "Target of Target Z", text = "Scoot's compact text-first Target of Target frame: the unit's name and health percent, nothing more. Replaces Blizzard's while enabled; positioned in Edit Mode and configured here." },
                betaBadge = true,
                variantGroup = "ufToT" },
            { key = "ufFocusTarget", label = "Target of Focus", module = "unitFrames", moduleSubId = "FocusTarget" },
            { key = "ufBoss", label = "Boss", module = "unitFrames", moduleSubId = "Boss",
                variant = "X",
                versionBadge = { label = "X", title = "Boss Frames X", text = "Blizzard's own Boss frames, restyled in place by Scoot. All five share one configuration." },
                variantGroup = "ufBoss", groupFallback = true, hideBadgesWhenDisabled = true },
            { key = "ufzBoss", label = "Boss", module = "unitFramesZ", moduleSubId = "Boss",
                variant = "Z",
                versionBadge = { label = "Z", title = "Boss Frames Z", text = "Scoot's own text-first Boss frames, replacing Blizzard's while enabled. The five frames stack as one block you position in Edit Mode and share the configuration on this page." },
                betaBadge = true,
                variantGroup = "ufBoss" },
            -- Last row of Unit Frames, and Z-only: the X variant is configured
            -- per frame, on each frame's own page above. alwaysShow keeps the row
            -- visible while X is selected so the Z badge can still explain what
            -- this is — grayed out is exactly when someone needs to ask.
            { key = "castBarZ", label = "Cast Bars", module = "castBars", moduleSubId = "castBarZ",
                variant = "Z",
                versionBadge = { label = "Z", title = "Cast Bar Z", text = "Scoot's own cast bars, drawn as filling text instead of a bar. Positioned freely in Edit Mode and configured here." },
                alwaysShow = true },
        },
    },
    {
        key = "groupFrames",
        label = "Group Frames",
        collapsible = true,
        children = {
            { key = "gfParty", label = "Party Frames", module = "groupFrames", moduleSubId = "party" },
            { key = "gfRaid", label = "Raid Frames", module = "groupFrames", moduleSubId = "raid" },
            { key = "gfAuraTracking", label = "Aura Tracking", module = "groupFrames", moduleSubId = "auraTracking", betaBadge = true },
        },
    },
    {
        key = "actionBars",
        label = "Action Bars",
        collapsible = true,
        children = {
            { key = "actionBars18", label = "Action Bars 1-8", module = "actionBars" },
            { key = "petBar", label = "Pet Bar", module = "actionBars" },
            { key = "stanceBar", label = "Stance Bar", module = "actionBars" },
            { key = "microBar", label = "Micro Bar", module = "actionBars" },
            { key = "extraAbilities", label = "Extra Abilities", module = "extraAbilities" },
        },
    },
    {
        key = "buffsDebuffs",
        label = "Buffs/Debuffs",
        collapsible = true,
        children = {
            { key = "buffs", label = "Buffs", module = "buffsDebuffs", moduleSubId = "buffs" },
            { key = "debuffs", label = "Debuffs", module = "buffsDebuffs", moduleSubId = "debuffs" },
        },
    },
    {
        key = "sct",
        label = "Scrolling Combat Text",
        collapsible = true,
        children = {
            { key = "sctDamage", label = "Damage Numbers", module = "sct" },
        },
    },
    -- Reports sits last among real sections; Debug is hidden by default and
    -- only appears below it via /scoot debugmenu.
    {
        key = "reports",
        label = "Reports",
        collapsible = true,
        children = {
            { key = "reportsWidget", label = "Widget", module = "widget" },
            { key = "reportsList", label = "Config", module = "widget" },
        },
    },
    {
        key = "debug",
        label = "Debug",
        collapsible = true,
        hidden = true,  -- Hidden by default, shown via /scoot debugmenu
        children = {
            { key = "debugMenu", label = "Debug Menu" },
        },
    },
}
