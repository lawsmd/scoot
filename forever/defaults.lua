--------------------------------------------------------------------------------
-- forever/defaults.lua
-- The settings panel's Defaults button for Camelot.
--
-- Camelot ships its own starting values, so a page has three defaults:
-- Camelot's, the values registered with DB.RegisterDefaults, and one per
-- Blizzard Edit Mode preset, Modern and Classic, the same frame with the
-- preset's values (DB.RegisterPreset, beside each feature's defaults) at the
-- preset's position (forever/startingpoints.lua). The button opens a choice
-- of the three, then a confirmation, then resets the page's scope and reloads.
--
-- This file is the host side of addon.DefaultsModel, which the shared panel
-- (ui/v2/settingspanel/navigation.lua) reads in place of Scoot's reset map.
--------------------------------------------------------------------------------

local _, addon = ...

local DB = addon.DB

local PageDefaults = {}
addon.PageDefaults = PageDefaults

--------------------------------------------------------------------------------
-- Scopes
--------------------------------------------------------------------------------
-- What each page owns. `prefixes` and `paths` select settings paths, `exclude`
-- takes prefixes back out, `layouts` names layout entries (a trailing "." is a
-- prefix), `documents` names documents. A Features page switch is never cleared.
-- `shared` names, for the confirmation, the settings other pages also read.

local UNIT_SHARED = { "unitFrames.showBarText", "unitFrames.borderStyle" }
local UNIT_SHARED_NOTE = "the bar numbers and the frame border, which every unit frame shares"

local function unitScope(key)
    return {
        prefixes = { "unitFrames." .. key .. "." },
        paths = UNIT_SHARED,
        layouts = { key },
        shared = UNIT_SHARED_NOTE,
    }
end

local SCOPES = {
    tooltip = { prefixes = { "tooltip." } },
    minimap = { prefixes = { "minimap." }, layouts = { "minimap" } },
    chatCustomize = { prefixes = { "chat." }, layouts = { "chat" } },
    objectiveTracker = {
        prefixes = { "objectiveTracker." },
        exclude = { "objectiveTracker.current." },
        layouts = { "objectiveTracker" },
        shared = "the fade in instanced combat, which Current Objectives shares",
    },
    -- The Quest Progress Text row is Quality of Life > Misc's over the same
    -- two keys (forever/qualityoflife/messages.lua), so the page resets them.
    currentObjectives = {
        prefixes = { "objectiveTracker.current." },
        paths = { "qol.messagesOffsetX", "qol.messagesOffsetY" },
        layouts = { "currentObjectives", "currentObjectivesCards" },
        shared = "the place of the error and quest text, which Quality of Life > Misc shares",
    },
    -- Quality of Life: Scoot's four shared pages (forever/qualityoflife/host.lua
    -- holds their keys) and Misc, each over its own keys under qol.
    qolEditMode = { paths = { "qol.editModeNudgeArrows", "qol.editModeSubGrid" } },
    qolLootVendors = { paths = { "qol.autoRepairMode", "qol.sellGreyItems", "qol.quickLoot" } },
    qolQuests = { paths = { "qol.showMapCoordinates", "qol.showQuestLogCount" } },
    qolSmallFixes = {
        paths = { "qol.modifierTargetShift", "qol.modifierTargetCtrl", "qol.modifierTargetAlt" },
    },
    qolMisc = {
        paths = { "qol.messagesOffsetX", "qol.messagesOffsetY", "qol.hideErrorMessages" },
        shared = "the place of the error and quest text, which Current Objectives shares",
    },
    qolAnimations = {
        paths = { "qol.animFood", "qol.animDrink", "qol.animCampfire" },
        layouts = { "qolAnimations" },
    },
    ufPlayer = unitScope("player"),
    ufTarget = unitScope("target"),
    ufFocus = unitScope("focus"),
    ufTargetOfTarget = unitScope("targettarget"),
    ufPet = unitScope("pet"),
    castBarPlayer = {
        prefixes = { "castBars.player.", "castBars.castTime" },
        paths = { "castBars.showSpark" },
        layouts = { "castBarPlayer" },
        shared = "the spark and the cast time readout, which every cast bar shares",
    },
    resourceDisplayGlobal = {
        prefixes = { "personalResourceDisplay." },
        exclude = { "personalResourceDisplay.health.", "personalResourceDisplay.power.",
                    "personalResourceDisplay.castBar.", "personalResourceDisplay.classResource." },
        layouts = { "personalResourceDisplay" },
    },
    resourceDisplayHealth = { prefixes = { "personalResourceDisplay.health." } },
    resourceDisplayPower = { prefixes = { "personalResourceDisplay.power." } },
    resourceDisplayResource = { prefixes = { "personalResourceDisplay.classResource." } },
    resourceDisplayCastBar = { prefixes = { "personalResourceDisplay.castBar." } },
    actionBarClusters = {
        prefixes = { "actionBars.text." },
        paths = { "actionBars.nextClusterId" },
        layouts = { "actionBarCluster." },
        documents = { "actionBars.clusters", "actionBars.memberMemory" },
    },
    actionBarMicroBags = {
        prefixes = { "actionBars.microBags." },
        layouts = { "microMenu", "bagBar", "microBags" },
    },
    actionBarStance = {
        prefixes = { "actionBars.stance.", "actionBars.visibility.stanceBar." },
        layouts = { "stanceBar" },
    },
}

local function startsWith(s, prefix)
    return s:sub(1, #prefix) == prefix
end

local function inScope(scope, path)
    if addon.Features and addon.Features.IsSwitchPath and addon.Features.IsSwitchPath(path) then
        return false
    end
    for _, p in ipairs(scope.exclude or {}) do
        if startsWith(path, p) then return false end
    end
    for _, p in ipairs(scope.paths or {}) do
        if path == p then return true end
    end
    for _, p in ipairs(scope.prefixes or {}) do
        if startsWith(path, p) then return true end
    end
    return false
end

local function layoutInScope(scope, key)
    for _, name in ipairs(scope.layouts or {}) do
        if key == name or (name:sub(-1) == "." and startsWith(key, name)) then return true end
    end
    return false
end

function PageDefaults.Has(navKey)
    return SCOPES[navKey] ~= nil
end

--------------------------------------------------------------------------------
-- The reset
--------------------------------------------------------------------------------

--- Clear everything the page owns, in this profile: its settings, its frame's
--- position in every layout with the Dynamic Layouts record, its documents.
--- `which` "modern" or "classic" then writes that preset's values. A cleared
--- position falls back to the default of the profile's own start, so a page
--- reset to another start stores that start's position in the active layout.
--- The caller reloads.
function PageDefaults.Reset(navKey, which)
    local scope = SCOPES[navKey]
    if not scope then return false end

    for _, path in ipairs(DB.StoredKeys("settings")) do
        if inScope(scope, path) then DB.Set(path, nil) end
    end
    for _, key in ipairs(DB.StoredKeys("layout")) do
        if layoutInScope(scope, key) then DB.SetLayout(key, nil) end
    end
    for _, key in ipairs(scope.documents or {}) do
        DB.SetDocument(key, nil)
    end

    if DB.PresetSet(which) then
        DB.EachPreset(which, function(path, value)
            if inScope(scope, path) then DB.Set(path, value) end
        end)
        for _, key in ipairs(scope.documents or {}) do
            local doc = DB.PresetDocument(which, key)
            if doc then DB.SetDocument(key, doc) end
        end
    end

    local SP = addon.StartingPoints
    local start = which == "camelot" and "camelot" or (SP and SP.PresetName(which))
    local layoutName = addon.EditMode and addon.EditMode.GetActiveLayoutName and addon.EditMode.GetActiveLayoutName()
    if SP and start and layoutName and start ~= DB.StartingPoint() then
        for _, key in ipairs(scope.layouts or {}) do
            local record = SP.DefaultFor(key, start)
            if record then
                DB.SetLayout(key, { positions = { [layoutName] = {
                    point = record.point, x = record.x, y = record.y,
                } } })
            end
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- The dialogs
--------------------------------------------------------------------------------

local LABELS = { camelot = "Camelot Default", modern = "Modern Default", classic = "Classic Default" }

local function confirm(navKey, title, which)
    local scope = SCOPES[navKey]
    local text = string.format(
        "Are you sure?\n\n%s returns to %s: every setting, and its position in every layout. The UI reloads, and this cannot be undone.",
        title, LABELS[which])
    if scope.shared then
        text = text .. "\n\nThis also resets " .. scope.shared .. "."
    end
    addon.UI.Controls:ShowDialog("PAGE_DEFAULTS_CONFIRM", {
        text = text,
        acceptText = "Reset & Reload", acceptWidth = 130,
        cancelText = CANCEL or "Cancel",
        onAccept = function()
            if InCombatLockdown() then return end
            PageDefaults.Reset(navKey, which)
            ReloadUI()
        end,
    })
end

function PageDefaults.Click(navKey, title)
    if InCombatLockdown() or not SCOPES[navKey] then return end
    if not (addon.UI and addon.UI.Controls and addon.UI.Controls.ShowDialog) then return end
    title = title or navKey
    addon.UI.Controls:ShowDialog("PAGE_DEFAULTS_CHOOSE", {
        text = string.format("Reset %s to:\n\nCamelot, the setup Camelot ships with.\nModern, Forever's own look in the Modern preset's place.\nClassic, the vanilla look in the Classic preset's place.", title),
        acceptText = "Camelot",
        extraButtons = {
            { text = "Modern", onClick = function() confirm(navKey, title, "modern") end },
            { text = "Classic", onClick = function() confirm(navKey, title, "classic") end },
        },
        cancelText = CANCEL or "Cancel",
        onAccept = function() confirm(navKey, title, "camelot") end,
    })
end

addon.DefaultsModel = {
    Has = PageDefaults.Has,
    Click = PageDefaults.Click,
    tooltipTitle = "Defaults",
    tooltipText = "Camelot Default returns this page to the setup Camelot ships with. Modern Default and Classic Default draw it the way Blizzard's Modern or Classic preset does, in the preset's place.\n\nEach one also resets the frame's position and reloads the UI.",
}

--------------------------------------------------------------------------------
-- /camelot defaults
--------------------------------------------------------------------------------

local function show(value)
    if type(value) == "table" then
        local parts = {}
        for i, v in ipairs(value) do parts[i] = string.format("%.2f", v) end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(value)
end

--- Every path a page owns that has a default, a stock value or a stored value,
--- with all three; then its stored layout entries and documents.
function PageDefaults.Dump(navKey)
    local lines, push = addon.DebugLines()
    local scope = navKey and SCOPES[navKey]
    if not scope then
        push("Pages with a Defaults button:")
        local keys = {}
        for k in pairs(SCOPES) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do push("  %s", k) end
        push("")
        push("/camelot defaults <page> lists one page's keys.")
        addon.DebugShowWindow("Camelot defaults", lines)
        return
    end

    local seen, paths = {}, {}
    local function add(path)
        if not seen[path] and inScope(scope, path) then
            seen[path] = true
            paths[#paths + 1] = path
        end
    end
    for _, path in ipairs(DB.StoredKeys("settings")) do add(path) end
    DB.EachDefault(function(path) add(path) end)
    for _, set in ipairs(DB.PRESETS) do
        DB.EachPreset(set, function(path) add(path) end)
    end
    table.sort(paths)

    local profile = DB.Profile()
    local function preset(set, path)
        local value = DB.Preset(set, path)
        return value == nil and "same" or show(value)
    end
    push("Profile start: %s", DB.StartingPoint())
    push("%s: path | stored | Camelot | Modern | Classic", navKey)
    for _, path in ipairs(paths) do
        push("  %s | %s | %s | %s | %s", path, show(profile and profile.settings[path]),
            show(DB.Default(path)), preset("modern", path), preset("classic", path))
    end
    push("")
    push("Layout entries:")
    for _, key in ipairs(DB.StoredKeys("layout")) do
        if layoutInScope(scope, key) then push("  %s", key) end
    end
    for _, key in ipairs(scope.documents or {}) do
        push("Document %s: %s", key, DB.GetDocument(key) and "stored" or "not stored")
    end
    addon.DebugShowWindow("Camelot defaults: " .. navKey, lines)
end

addon:RegisterSlashCommand({
    name = "defaults",
    help = "list a settings page's keys: stored value, then the Camelot, Modern and Classic defaults",
    handler = function(_, rest) PageDefaults.Dump(rest and rest[1]) end,
})
