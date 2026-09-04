-- debug/inspect.lua - /scoot debug inspect
local addonName, addon = ...

local function DebugInspectState()
    if not addon.Inspect or not addon.Inspect._DebugState then
        addon:Print("Inspect service not loaded.")
        return
    end
    local s = addon.Inspect:_DebugState()
    addon:Print("== Inspect Service ==")
    addon:Print("  Started: " .. tostring(s.started))
    addon:Print("  State: " .. tostring(s.state))
    addon:Print("  Ticker running: " .. tostring(s.tickerRunning))
    addon:Print("  Queue length: " .. tostring(s.queueLength))
    if s.pendingGuid then
        addon:Print(string.format("  In flight: %s (%s)", tostring(s.pendingUnit), tostring(s.pendingGuid)))
    end
    addon:Print(string.format("  Quiet remaining: %.1fs", s.quietRemaining))
    addon:Print("  InspectFrame shown: " .. tostring(s.frameShown))
    addon:Print("  Cached members: " .. tostring(s.cacheCount))
    if s.pauseReasons and s.pauseReasons ~= "" then
        addon:Print("  Paused by: " .. s.pauseReasons)
    end
end

local function DebugInspectCache()
    if not addon.Inspect then
        addon:Print("Inspect service not loaded.")
        return
    end
    addon:Print("== Inspect Cache ==")
    local now = GetTime()
    local count = 0
    for guid, entry in pairs(addon.Inspect:GetAll()) do
        count = count + 1
        addon:Print(string.format("  %s: ilvl %s, %s, age %ds",
            tostring(entry.name or guid),
            tostring(entry.itemLevel or "?"),
            tostring(entry.specName or "?"),
            math.floor(now - (entry.time or 0))))
    end
    if count == 0 then
        addon:Print("  (empty)")
    end
end

addon:RegisterDebugCommand({
    name = "inspect", help = "inspect service", default = "state",
    verbs = {
        { word = "state", help = "service state", fn = DebugInspectState },
        { word = "cache", help = "cache contents", fn = DebugInspectCache },
    },
})
