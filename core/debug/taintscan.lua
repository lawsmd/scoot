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
-- sites), and every tainted global, grouped by the addon that tainted it.
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
}

local GLOBALS_PER_SOURCE = 200

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
