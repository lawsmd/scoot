-- taintscan.lua - Which fields on Blizzard's Edit Mode entry path carry addon taint
--
-- A secret-value error "while execution tainted by <addon>" from a stack that
-- is all Blizzard code means one of the values that stack read had been
-- written by addon code. Taint on a table field lasts the session, so
-- the field is still marked after the error: issecurevariable names it with no
-- taint log running. This walks the tables Edit Mode reads on its way in (the
-- manager, the account settings, every registered system frame, the party and
-- compact frames, the panel manager tables) and lists every tainted key, the
-- widget methods shadowed on a frame's own table (hooksecurefunc and override
-- sites), and every tainted global, grouped by the addon that tainted it. It
-- opens with the fields each stage of the game menu's Edit Mode path writes,
-- in path order, so the first tainted one names the stage the taint entered
-- at; a clean show or entry since rewrites them secure, so the scan runs
-- right after the error, before anything else is opened. A second part reads
-- the world map's quest pin path the same way, and keeps the blocked
-- SetPassThroughButtons calls with the first tainted value at each.
-- Usage: /<slash> debug taintscan
local addonName, addon = ...

-- name, depth: depth 0 checks the root's own keys, each level one table further.
local ROOTS = {
    { "EditModeManagerFrame", 3 },
    { "EditModeSystemSettingsDialog", 1 },
    { "GameMenuFrame", 1 },
    { "FramePositionDelegate", 1 },
    { "UIPanelWindows", 1 },
    { "UISpecialFrames", 0 },
    -- The Escape path: CloseAllBags, then each open panel's hide, then the
    -- world map's quest pins.
    { "WorldMapFrame", 2 },
    { "QuestMapFrame", 2 },
    { "QuestScrollFrame", 1 },
    { "ContainerFrameContainer", 1 },
    { "ContainerFrame1", 1 },
    { "FriendsFrame", 1 },
    { "TimeManagerFrame", 1 },
    { "PartyFrame", 2 },
    { "CompactPartyFrame", 2 },
    { "CompactRaidFrameContainer", 1 },
    { "CompactRaidFrameManager", 1 },
    { "DefaultCompactUnitFrameOptions", 1 },
    { "DefaultCompactUnitFrameSetupOptions", 1 },
    { "PlayerFrame", 2 },
    { "TargetFrame", 2 },
    { "FocusFrame", 2 },
    { "PetFrame", 2 },
    { "TargetFrameToT", 1 },
    { "MainActionBar", 2 },
    { "MainMenuBar", 2 },
    { "MultiBarBottomLeft", 2 },
    { "MultiBarBottomRight", 2 },
    { "MultiBarRight", 2 },
    { "MultiBarLeft", 2 },
    { "MultiBar5", 2 },
    { "MultiBar6", 2 },
    { "MultiBar7", 2 },
    { "ActionBarActionEventsFrame", 1 },
    { "ActionBarButtonEventsFrame", 1 },
    { "ActionBarButtonRangeCheckFrame", 1 },
    { "ActionBarButtonUsableWatcherFrame", 1 },
    { "StanceBar", 2 },
    { "PetActionBar", 2 },
    { "PossessActionBar", 2 },
    { "StatusTrackingBarManager", 2 },
    { "MainStatusTrackingBarContainer", 1 },
    { "SecondaryStatusTrackingBarContainer", 1 },
    { "DurabilityFrame", 1 },
    { "EncounterBar", 1 },
    { "PlayerCastingBarFrame", 1 },
    { "MinimapCluster", 1 },
    { "ObjectiveTrackerFrame", 1 },
    { "PersonalResourceDisplayFrame", 1 },
    { "UIErrorsFrame", 0 },
    -- Forever's gamepad UI: every panel close runs the frame controls manager
    -- and the binding stack into a protected call. Absent on retail.
    { "GamepadMode", 2 },
    { "GamepadSharedUtility", 3 },
    { "GamepadMainActionBarFrame", 3 },
    { "SpellFlyout", 1 },
    { "InputDeviceIconSetManager", 1 },
    -- The game menu's OnShow and OnHide run UpdateMicroButtons over every
    -- micro button before the menu builds its buttons, and the settings
    -- window shares the menuOpen trigger with the menu. Retail lacks a few
    -- of Forever's buttons.
    { "SettingsPanel", 1 },
    { "MicroMenuContainer", 1 },
    { "MicroMenu", 1 },
    { "BagsBar", 1 },
    { "MainMenuMicroButton", 1 },
    { "CharacterMicroButton", 1 },
    { "ProfessionMicroButton", 1 },
    { "SpellbookMicroButton", 1 },
    { "PlayerSpellsMicroButton", 1 },
    { "TalentMicroButton", 1 },
    { "LegacyMicroButton", 1 },
    { "QuestLogMicroButton", 1 },
    { "HousingMicroButton", 1 },
    { "GuildMicroButton", 1 },
    { "LFDMicroButton", 1 },
    { "AchievementMicroButton", 1 },
    { "CollectionsMicroButton", 1 },
    { "EJMicroButton", 1 },
    { "HelpMicroButton", 1 },
    { "StoreMicroButton", 1 },
}

local GLOBALS_PER_SOURCE = 200

-- The fields each stage of the game menu's Edit Mode path writes, in path
-- order: the menu's OnShow (Reset and AddButton), the panel manager's
-- SetUIPanel for a center panel, EnterEditMode, the account settings'
-- OnEditModeEnter, and the party frame preview's SetUpFrame and UpdateInRange.
-- A write marks the field with its writer's taint and a later secure write
-- clears it, so right after an error the first tainted marker is the stage
-- the taint entered at. { stage, root, key..., field }.
local MARKERS = {
    { "the game menu's OnShow", "GameMenuFrame", "buttonCount" },
    { "the game menu's OnShow", "GameMenuFrame", "nextLayoutIndex" },
    { "the panel manager's show", "FramePositionDelegate", "center" },
    { "EnterEditMode", "EditModeManagerFrame", "editModeActive" },
    { "OnEditModeEnter", "EditModeManagerFrame", "AccountSettings", "oldActionBarSettings" },
    { "the party frame preview", "CompactPartyFrameMember1", "newUnit" },
    { "the party frame preview", "CompactPartyFrameMember1", "isLootObject" },
    { "the party frame preview", "CompactPartyFrameMember1", "outOfRange" },
}

local function isFrame(t)
    return type(rawget(t, 0)) == "userdata"
end

local function keyText(k)
    if issecretvalue and issecretvalue(k) then return "[<secret key>]" end
    if type(k) == "string" then
        if k:match("^[%a_][%w_]*$") then return "." .. k end
        return string.format("[%q]", k)
    end
    if type(k) == "table" then
        if canaccesstable and not canaccesstable(k) then return "[<forbidden table>]" end
        local ok, name = pcall(function() return isFrame(k) and k:GetName() end)
        return "[" .. ((ok and name) or tostring(k)) .. "]"
    end
    return "[" .. tostring(k) .. "]"
end

-- issecurevariable(t, k) for a field, issecurevariable(name) for a global.
local function taintOf(...)
    local ok, secure, by = pcall(issecurevariable, ...)
    if not ok then return "unreadable" end
    if secure then return nil end
    return tostring(by or "?")
end

-- One marker's verdict: absent (the root or a step is missing, or the field
-- is nil), secure, unreadable, or the addon that wrote it.
local function markerVerdict(marker)
    local t = _G[marker[2]]
    for i = 3, #marker - 1 do
        if type(t) ~= "table" or (canaccesstable and not canaccesstable(t)) then return "absent" end
        local ok, step = pcall(rawget, t, marker[i])
        if not ok then return "unreadable" end
        t = step
    end
    if type(t) ~= "table" or (canaccesstable and not canaccesstable(t)) then return "absent" end
    local field = marker[#marker]
    local ok, value = pcall(rawget, t, field)
    if not ok then return "unreadable" end
    if type(value) == "nil" then return "absent" end
    return taintOf(t, field) or "secure"
end

-- The world map's data providers write dataProviderEventsCount on every show,
-- so a mark on QUEST_LOG_UPDATE after OnShow means that show ran as an addon.
-- A pin pool keeps the mark of the show that created it for the session, and
-- every later pin read takes it. The first tainted show with clean pools is
-- the culprit; the stack names its caller.
local MAP_SHOWS_KEPT = 6
local mapShows = { clean = 0, tainted = {} }

local function taintedPools(map)
    local pools = rawget(map, "pinPools")
    local marked = {}
    if type(pools) ~= "table" then return marked end
    for k in next, pools do
        if type(k) == "string" and taintOf(pools, k) then marked[#marked + 1] = k end
    end
    table.sort(marked)
    return marked
end

local function onMapShow(map)
    local counts = rawget(map, "dataProviderEventsCount")
    local by = type(counts) == "table" and taintOf(counts, "QUEST_LOG_UPDATE")
    if not by then
        mapShows.clean = mapShows.clean + 1
        return
    end
    if #mapShows.tainted >= MAP_SHOWS_KEPT then return end
    mapShows.tainted[#mapShows.tainted + 1] = {
        when = date("%H:%M:%S"),
        by = by,
        combat = InCombatLockdown(),
        poolsBefore = mapShows.lastPools or {},
        poolsAfter = taintedPools(map),
        stack = debugstack(2, 40, 0),
    }
    mapShows.lastPools = mapShows.tainted[#mapShows.tainted].poolsAfter
end

addon.Events.OnAddonLoaded("Blizzard_WorldMap", function()
    if WorldMapFrame then WorldMapFrame:HookScript("OnShow", onMapShow) end
end)

-- The world map's quest pin path. QuestDataProviderMixin:RegisterEvents
-- registers a Supertracking.OnChanged callback on each show and
-- UnregisterEvents leaves it, so once the map has been shown its quest pins
-- are rebuilt on every supertrack change, shown or not. Each pin acquire
-- calls SetPassThroughButtons, which insecure code may not call in combat:
-- one tainted value on that path is a blocked action per pin, with a stack
-- that is all Blizzard's. The values the path reads are the provider, the
-- pin pool's slot, the pins, the highlight manager's quest, and the quest
-- object QuestCache holds for each pin. POIButtonUtil.GetStyle asks for that
-- object, QuestCache creates it on the first ask, and whoever asked first
-- wrote it.
local QUEST_PIN_TEMPLATE = "QuestPinTemplate"
local BLOCKED_KEPT = 5
local PINS_LISTED = 8
local KEYS_LISTED = 6
local CALLBACK_TYPE_FUNCTION = 2 -- CallbackRegistry.lua: MakeEnum("Closure", "Function")

local function readable(t)
    return type(t) == "table" and not (canaccesstable and not canaccesstable(t))
end

local function field(t, k)
    if not readable(t) then return nil end
    local ok, v = pcall(rawget, t, k)
    if ok then return v end
    return nil
end

-- Every string key of t that carries taint, as "key by addon", and the
-- number of string keys t has.
local function taintedKeys(t)
    local marked, total = {}, 0
    if not readable(t) then return marked, total end
    pcall(function()
        for k in next, t do
            if type(k) == "string" then
                total = total + 1
                local by = taintOf(t, k)
                if by then marked[#marked + 1] = k .. " by " .. by end
            end
        end
    end)
    table.sort(marked)
    return marked, total
end

local function keyList(marked)
    if #marked == 0 then return "none" end
    local shown = {}
    for i = 1, math.min(#marked, KEYS_LISTED) do shown[i] = marked[i] end
    local text = table.concat(shown, ", ")
    if #marked > KEYS_LISTED then
        text = text .. string.format(", and %d more", #marked - KEYS_LISTED)
    end
    return text
end

-- The map's quest provider: the entry of dataProviders built from
-- QuestDataProviderMixin, found by its methods' identity.
local function questProvider(map)
    local providers = field(map, "dataProviders")
    local mixin = _G.QuestDataProviderMixin
    if not (providers and type(mixin) == "table") then return nil end
    local found
    pcall(function()
        for provider in next, providers do
            if type(provider) == "table"
                and rawget(provider, "RefreshAllData") == mixin.RefreshAllData
                and rawget(provider, "GetPinTemplate") == mixin.GetPinTemplate then
                found = provider
            end
        end
    end)
    return found
end

-- Every quest pin the provider has ever placed, shown or pooled: AddQuest
-- writes dataProvider on a pin and nothing clears it.
local function questPins(map, provider)
    local pins = {}
    local canvas = field(field(map, "ScrollContainer"), "Child")
    if not (canvas and provider) then return pins end
    pcall(function()
        for _, child in ipairs({ canvas:GetChildren() }) do
            if rawget(child, "dataProvider") == provider then pins[#pins + 1] = child end
        end
    end)
    return pins
end

-- The watched quests and the quests on the map's zone, in that order, each
-- once: the quests the tracker asks QuestCache for and the ones the map does.
local function questsOnPath(map)
    local list, seen = {}, {}
    local function add(questID, key)
        if type(questID) ~= "number" then return end
        local entry = seen[questID]
        if not entry then
            entry = { id = questID }
            seen[questID] = entry
            list[#list + 1] = entry
        end
        entry[key] = true
    end
    pcall(function()
        for i = 1, C_QuestLog.GetNumQuestWatches() do
            add(C_QuestLog.GetQuestIDForQuestWatchIndex(i), "watched")
        end
    end)
    local mapID = field(map, "mapID")
    if type(mapID) == "number" then
        pcall(function()
            for _, info in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
                add(info.questID, "onMap")
            end
        end)
    end
    return list, mapID
end

local function questObject(questID)
    return field(field(_G.QuestCache, "objects"), questID)
end

-- Whether the provider's leaked callback is in the registry: true from the
-- first map show of the session on.
local function supertrackCallbackHeld(provider)
    local tables = field(_G.EventRegistry, "callbackTables")
    local callbacks = field(field(tables, CALLBACK_TYPE_FUNCTION), "Supertracking.OnChanged")
    return field(callbacks, provider) ~= nil
end

-- The path's rows in the order a pin refresh reads them, each { label,
-- verdict }, verdict nil when the row is secure.
local function questPinRows()
    local map = _G.WorldMapFrame
    local rows = {}
    if type(map) ~= "table" then return rows, nil end
    local provider = questProvider(map)

    local marked = taintedKeys(provider)
    rows[#rows + 1] = { "the quest provider's fields", #marked > 0 and keyList(marked) or nil }

    local pools = field(map, "pinPools")
    rows[#rows + 1] = { "the pin pool slot " .. QUEST_PIN_TEMPLATE,
        readable(pools) and taintOf(pools, QUEST_PIN_TEMPLATE) or nil }

    local pins = questPins(map, provider)
    local markedPins = 0
    for _, pin in ipairs(pins) do
        local keys = taintedKeys(pin)
        if #keys > 0 then
            markedPins = markedPins + 1
            if markedPins <= PINS_LISTED then
                rows[#rows + 1] = { string.format("quest pin %d", markedPins), keyList(keys) }
            end
        end
    end
    rows[#rows + 1] = { string.format("quest pins: %d placed so far, %d with tainted fields", #pins, markedPins),
        markedPins > PINS_LISTED and string.format("%d more not listed", markedPins - PINS_LISTED) or nil }

    local quests, mapID = questsOnPath(map)
    for _, entry in ipairs(quests) do
        local object = questObject(entry.id)
        local verdict
        if readable(object) then
            local creator = taintOf(object, "questID")
            local keys, total = taintedKeys(object)
            if creator then
                verdict = string.format("created by %s, %d of %d fields tainted", creator, #keys, total)
            elseif #keys > 0 then
                verdict = "created secure, tainted since: " .. keyList(keys)
            end
        end
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, entry.id)
        rows[#rows + 1] = {
            string.format("quest %d %s (%s%s%s), %s", entry.id, ok and title or "?",
                entry.watched and "watched" or "", entry.watched and entry.onMap and ", " or "",
                entry.onMap and "on the map" or "", readable(object) and "object in QuestCache" or "no object"),
            verdict,
        }
    end

    local manager = _G.POIButtonHighlightManager
    rows[#rows + 1] = { "POIButtonHighlightManager.questID", readable(manager) and taintOf(manager, "questID") or nil }

    return rows, { map = map, provider = provider, mapID = mapID }
end

local function firstTaintedRow()
    local ok, rows = pcall(questPinRows)
    if not ok then return "scan failed" end
    for _, row in ipairs(rows) do
        if row[2] then return row[1] .. ": " .. row[2] end
    end
    return "every row secure"
end

-- The blocked calls themselves, each with the first tainted row at that
-- moment: the hop the taint entered at, read with no taint log running.
local blockedPins = {}

addon.Events.On("taintscan", "ADDON_ACTION_BLOCKED", function(_, blamed, action)
    if type(action) ~= "string" or not action:find("SetPassThroughButtons", 1, true) then return end
    local last = blockedPins[#blockedPins]
    local now = GetTime()
    -- One refresh blocks two calls per pin; they are one entry.
    if last and now - last.at < 1 then
        last.count = last.count + 1
        return
    end
    local map = _G.WorldMapFrame
    local shown = false
    if type(map) == "table" then
        local ok, value = pcall(map.IsShown, map)
        shown = ok and value or false
    end
    local superTrack = _G.C_SuperTrack
    blockedPins[#blockedPins + 1] = {
        at = now,
        when = date("%H:%M:%S"),
        by = tostring(blamed),
        count = 1,
        combat = InCombatLockdown(),
        mapShown = shown,
        superTracked = superTrack and superTrack.GetSuperTrackedQuestID and superTrack.GetSuperTrackedQuestID() or nil,
        first = firstTaintedRow(),
    }
    if #blockedPins > BLOCKED_KEPT then table.remove(blockedPins, 1) end
end)

-- Whether a supertrack change set from Lua dispatches SUPER_TRACKING_CHANGED
-- inside the call. When it does, every handler runs as the caller, the map's
-- pin refresh among them, so a set from addon code blocks the pins in combat
-- and marks them out of it. The stack under this handler says which happened:
-- the C function and its caller are in it when the dispatch is inside the
-- call, and it ends at the event frame when the client dispatched it.
local STACK_LINES_KEPT = 10
local superTrackSeen = { client = 0, inCall = 0 }

addon.Events.On("taintscan", "SUPER_TRACKING_CHANGED", function()
    local stack = debugstack(2, 30, 0) or ""
    if not stack:find("SuperTrack", 1, true) then
        superTrackSeen.client = superTrackSeen.client + 1
        return
    end
    superTrackSeen.inCall = superTrackSeen.inCall + 1
    superTrackSeen.when = date("%H:%M:%S")
    superTrackSeen.combat = InCombatLockdown()
    superTrackSeen.stack = stack
end)

local function methodTable(frame)
    local mt = getmetatable(frame)
    local index = type(mt) == "table" and rawget(mt, "__index")
    return type(index) == "table" and index or nil
end

local function Scan()
    local lines, push = addon.DebugLines()
    local tainted, shadows, missing, forbidden = {}, {}, {}, {}
    local best = {}
    local fields, shadowCount = 0, 0

    local function walk(t, path, depth)
        if (best[t] or -1) >= depth then return end
        local first = best[t] == nil
        best[t] = depth

        -- Any read of a forbidden table throws, rawget included, so it is
        -- screened before the first touch.
        if canaccesstable and not canaccesstable(t) then
            if first then forbidden[#forbidden + 1] = path end
            return
        end

        local frame = isFrame(t)
        local methods = frame and methodTable(t)
        local children = {}

        local ok = pcall(function()
            for k, v in next, t do
                local text = keyText(k)
                if first then
                    fields = fields + 1
                    -- issecurevariable takes a string key only; a frame-keyed
                    -- set (snappedFrames and the like) has nothing to name.
                    local by = type(k) == "string" and taintOf(t, k) or nil
                    if by then tainted[#tainted + 1] = string.format("%-70s by %s", path .. text, by) end
                    if methods and type(k) == "string" and methods[k] ~= nil and type(v) == "function" then
                        shadowCount = shadowCount + 1
                        if by then shadows[#shadows + 1] = string.format("%-70s by %s", path .. text, by) end
                    end
                end
                if type(v) == "table" and depth > 0 then
                    children[#children + 1] = { v, path .. text }
                end
            end
        end)
        if not ok then
            tainted[#tainted + 1] = string.format("%-70s (could not walk: forbidden or secret)", path)
            return
        end

        for _, child in ipairs(children) do
            walk(child[1], child[2], depth - 1)
        end
    end

    for _, root in ipairs(ROOTS) do
        local t = _G[root[1]]
        if type(t) == "table" then
            walk(t, root[1], root[2])
        else
            missing[#missing + 1] = root[1]
        end
    end
    for i = 1, 5 do
        local name = "CompactPartyFrameMember" .. i
        local t = _G[name]
        if type(t) == "table" then walk(t, name, 2) end
    end

    local brand = addon.Brand or addonName

    -- Blizzard's button lists are arrays, which issecurevariable cannot
    -- name, so an addon button in one is found by its name instead. One
    -- such entry taints every button the list's loop reaches after it.
    local listed = {}
    for _, listName in ipairs({ "ActionBarButtonEventsFrame", "ActionBarActionEventsFrame" }) do
        local owner = _G[listName]
        local list = type(owner) == "table" and rawget(owner, "frames")
        if type(list) == "table" then
            for i, f in pairs(list) do
                local ok, name = pcall(function() return f:GetName() end)
                name = ok and name or nil
                if not name or name:find("^" .. brand) then
                    listed[#listed + 1] = string.format("%s.frames[%s] %s", listName, tostring(i), name or "unnamed")
                end
            end
        end
    end

    -- The range and usable watchers keep a table per action slot, and the
    -- Blizzard button on a slot reads it; one made by an addon button
    -- taints that read.
    for _, listName in ipairs({ "ActionBarButtonRangeCheckFrame", "ActionBarButtonUsableWatcherFrame" }) do
        local owner = _G[listName]
        local actions = type(owner) == "table" and rawget(owner, "actions")
        if type(actions) == "table" then
            for slot, set in pairs(actions) do
                if type(set) == "table" then
                    for f in pairs(set) do
                        local ok, name = pcall(function() return f:GetName() end)
                        name = ok and name or nil
                        if not name or name:find("^" .. brand) then
                            listed[#listed + 1] = string.format("%s.actions[%s] %s", listName, tostring(slot), name or "unnamed")
                        end
                    end
                end
            end
        end
    end

    -- Globals: every tainted name, grouped by source. Names carrying this
    -- addon's brand are the addon's own and are counted, not listed.
    local bySource, ownCount, total = {}, {}, 0
    for k, v in next, _G do
        if type(k) == "string" then
            total = total + 1
            local by = taintOf(k)
            if by then
                if k:find("^" .. brand) or k:find("^SLASH_" .. brand:upper()) then
                    ownCount[by] = (ownCount[by] or 0) + 1
                else
                    bySource[by] = bySource[by] or {}
                    local list = bySource[by]
                    list[#list + 1] = string.format("%-56s %s", k, type(v))
                end
            end
        end
    end

    table.sort(tainted)
    table.sort(shadows)

    push("Taint scan, %s", date("%Y-%m-%d %H:%M:%S"))
    push("addon %s, taintLog %s, in combat %s, Edit Mode shown %s", addonName,
        tostring(GetCVar and GetCVar("taintLog")), tostring(InCombatLockdown()),
        tostring(EditModeManagerFrame and EditModeManagerFrame:IsShown()))
    push("fields checked: %d, globals checked: %d", fields, total)
    if #missing > 0 then push("roots absent on this client: %s", table.concat(missing, ", ")) end
    push("")

    push("Where the taint entered: the fields each stage of the game menu's Edit Mode path writes, in path order.")
    push("  The first tainted one is the stage; a clean show or entry since rewrites them secure.")
    for _, marker in ipairs(MARKERS) do
        local path = marker[2]
        for i = 3, #marker do path = path .. "." .. marker[i] end
        push("  %-28s %-62s %s", marker[1], path, markerVerdict(marker))
    end
    push("")

    push("Tainted fields on the Edit Mode path (%d):", #tainted)
    if #tainted == 0 then push("  none") end
    for _, row in ipairs(tainted) do push("  %s", row) end
    push("")

    push("Addon or unnamed frames in Blizzard's button and watcher lists (%d):", #listed)
    if #listed == 0 then push("  none") end
    for _, row in ipairs(listed) do push("  %s", row) end
    push("")

    table.sort(forbidden)
    push("Tables addon code cannot read, skipped (%d):", #forbidden)
    if #forbidden == 0 then push("  none") end
    for _, path in ipairs(forbidden) do push("  %s", path) end
    push("")

    push("Widget methods shadowed on a frame's own table: %d, tainted %d", shadowCount, #shadows)
    push("  a hooksecurefunc on a frame method, or a Blizzard override, puts the key here")
    if #shadows == 0 then push("  none") end
    for _, row in ipairs(shadows) do push("  %s", row) end
    push("")

    push("World map shows that ran as an addon (%d kept, %d clean shows):", #mapShows.tainted, mapShows.clean)
    if #mapShows.tainted == 0 then push("  none") end
    for i, show in ipairs(mapShows.tainted) do
        push("  %d. %s by %s, in combat %s", i, show.when, show.by, tostring(show.combat))
        push("     pin pools marked before: %s", #show.poolsBefore > 0 and table.concat(show.poolsBefore, ", ") or "none")
        push("     pin pools marked after: %s", #show.poolsAfter > 0 and table.concat(show.poolsAfter, ", ") or "none")
        for line in show.stack:gmatch("[^\n]+") do push("     %s", line) end
    end
    push("")

    push("Quest pin path: what the world map's quest pin refresh reads, in the order it reads it.")
    local okRows, rows, context = pcall(questPinRows)
    if not okRows then
        push("  could not read: %s", tostring(rows))
    elseif not context then
        push("  no world map on this client")
    else
        local okShown, mapShown = pcall(context.map.IsShown, context.map)
        push("  map id %s, shown %s; the provider's Supertracking.OnChanged callback held: %s",
            tostring(context.mapID), tostring(okShown and mapShown),
            context.provider and tostring(supertrackCallbackHeld(context.provider)) or "no quest provider found")
        push("  held means the map rebuilds its quest pins on every supertrack change, shown or hidden")
        for _, row in ipairs(rows) do
            push("  %-78s %s", row[1], row[2] or "secure")
        end
    end
    push("")

    push("Blocked SetPassThroughButtons calls (%d kept):", #blockedPins)
    if #blockedPins == 0 then push("  none") end
    for i, entry in ipairs(blockedPins) do
        push("  %d. %s by %s, %d call(s), in combat %s, map shown %s, supertracked quest %s", i, entry.when, entry.by,
            entry.count, tostring(entry.combat), tostring(entry.mapShown), tostring(entry.superTracked))
        push("     first tainted row then: %s", entry.first)
    end
    push("")

    push("Supertrack changes seen: %d dispatched by the client, %d inside a Lua call",
        superTrackSeen.client, superTrackSeen.inCall)
    push("  inside a call, every handler runs as the caller, the map's pin refresh among them")
    if superTrackSeen.stack then
        push("  the last one, %s, in combat %s:", superTrackSeen.when, tostring(superTrackSeen.combat))
        local shown = 0
        for line in superTrackSeen.stack:gmatch("[^\n]+") do
            shown = shown + 1
            if shown > STACK_LINES_KEPT then break end
            push("     %s", line)
        end
    end
    push("")

    local sources = {}
    for by in pairs(bySource) do sources[#sources + 1] = by end
    for by in pairs(ownCount) do if not bySource[by] then sources[#sources + 1] = by end end
    table.sort(sources)
    push("Tainted globals by source:")
    if #sources == 0 then push("  none") end
    for _, by in ipairs(sources) do
        local list = bySource[by] or {}
        table.sort(list)
        push("  %s: %d branded names (not listed), %d other names", by, ownCount[by] or 0, #list)
        for i, row in ipairs(list) do
            if i > GLOBALS_PER_SOURCE then
                push("    ... %d more", #list - GLOBALS_PER_SOURCE)
                break
            end
            push("    %s", row)
        end
    end

    addon.DebugShowWindow("Taint scan", lines)
end

addon:RegisterDebugCommand({
    name = "taintscan",
    help = "list tainted fields on Blizzard's Edit Mode path, shadowed frame methods and tainted globals",
    handler = function() Scan() end,
})
