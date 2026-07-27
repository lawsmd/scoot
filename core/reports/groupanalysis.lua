-- reports/groupanalysis.lua - Group Analysis report: data model + registration
--
-- Lists every player in the party or raid with class-colored name, spec, and
-- overall item level. The local player is read directly; everyone else comes
-- from the passive inspect service cache, so cells start blank and fill in as
-- the background scan (or the user's own inspects) populate it.
local addonName, addon = ...

local Reports = addon.Reports
local GA = {}
Reports.GroupAnalysis = GA

--------------------------------------------------------------------------------
-- Guarded reads
--------------------------------------------------------------------------------

-- Identity can be secret in instanced content; a blank cell beats an error.
local function safeUnitName(unit)
    local ok, n = pcall(UnitName, unit)
    if not ok or n == nil then return nil end
    if issecretvalue and issecretvalue(n) then return nil end
    if type(n) ~= "string" then return nil end
    return n:match("^([^%-]+)") or n
end

local function localPlayerEntry()
    local entry = {
        unit = "player",
        isPlayer = true,
        name = safeUnitName("player"),
    }

    local gOk, guid = pcall(UnitGUID, "player")
    if gOk then entry.guid = guid end

    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        local _, specName = GetSpecializationInfo(specIndex)
        entry.specName = specName
    end

    local iOk, _, equipped = pcall(GetAverageItemLevel)
    if iOk and type(equipped) == "number" and equipped > 0 then
        entry.itemLevel = math.floor(equipped)
    end

    return entry
end

--------------------------------------------------------------------------------
-- Snapshot
--------------------------------------------------------------------------------

-- The inspect service is consumed through this one accessor so the report
-- only depends on a single point of contact.
local function getInspectInfo(guid)
    if not guid or not addon.Inspect then return nil end
    return addon.Inspect:GetUnitInfo(guid)
end

local function buildMemberEntry(unit)
    local entry = { unit = unit }

    local gOk, guid = pcall(UnitGUID, unit)
    if gOk then entry.guid = guid end

    entry.name = safeUnitName(unit)

    local cached = getInspectInfo(entry.guid)
    if cached then
        entry.specName = cached.specName
        entry.itemLevel = cached.itemLevel
        -- Inspect-time name backfills a live read blocked by identity secrecy.
        if not entry.name then entry.name = cached.name end
    end

    return entry
end

-- Returns { mode = "solo"|"party"|"raid", entries = { entry } } where entry =
-- { unit, guid?, name?, classR/classG/classB?, specName?, itemLevel?, isPlayer? }.
-- nil fields render as blank cells.
function GA.BuildSnapshot()
    local snapshot = { entries = {} }

    if IsInRaid() then
        snapshot.mode = "raid"
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local entry = buildMemberEntry(unit)
            local selfOk, isSelf = pcall(UnitIsUnit, unit, "player")
            if selfOk and isSelf then
                entry = localPlayerEntry()
                entry.unit = unit
            end
            table.insert(snapshot.entries, entry)
        end
    elseif IsInGroup() then
        snapshot.mode = "party"
        table.insert(snapshot.entries, localPlayerEntry())
        for i = 1, GetNumGroupMembers() - 1 do
            table.insert(snapshot.entries, buildMemberEntry("party" .. i))
        end
    else
        -- Not in a group: a single self row still demonstrates the report.
        snapshot.mode = "solo"
        table.insert(snapshot.entries, localPlayerEntry())
    end

    -- Class colors resolve per unit token (guarded helper; nil means white).
    for _, entry in ipairs(snapshot.entries) do
        local r, g, b = addon.GetClassColorRGB(entry.unit)
        entry.classR, entry.classG, entry.classB = r, g, b
    end

    return snapshot
end

--------------------------------------------------------------------------------
-- Change subscription
--------------------------------------------------------------------------------
-- The panel subscribes while open: roster changes and combat drop trigger a
-- rebuild; each inspect-service update fills newly available cells.
--------------------------------------------------------------------------------

local subscriberCallback = nil
local eventFrame = nil

function GA.Subscribe(cb)
    subscriberCallback = cb

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event)
            if subscriberCallback then
                subscriberCallback(event)
            end
        end)
    end
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    addon:RegisterMessage("SCOOT_INSPECT_UPDATED", function(_, guid)
        if subscriberCallback then
            subscriberCallback("SCOOT_INSPECT_UPDATED", guid)
        end
    end)
end

function GA.Unsubscribe()
    subscriberCallback = nil
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    addon:UnregisterMessage("SCOOT_INSPECT_UPDATED")
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

Reports:Register({
    id = "groupAnalysis",
    label = "Group Analysis",
    description = "Lists every player in your party or raid with class-colored name, spec, and item level. Details for other players fill in as Scoot's background scan completes.",
    order = 10,
    Run = function()
        -- Warm the cache the moment the report runs, even on a cold start.
        if addon.Inspect then
            addon.Inspect:EnsureStarted()
        end
        local Panel = addon.UI and addon.UI.Reports and addon.UI.Reports.GroupAnalysisPanel
        if Panel then
            Panel:OpenOrRefresh()
        end
    end,
})
