--------------------------------------------------------------------------------
-- bars/debug.lua
-- Power bar debug trace system and position diagnostics.
-- /scoot debug powerbar trace on|off|log|clear
-- /scoot debug powerbarpos [simulate]
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Create module namespace
addon.BarsDebug = addon.BarsDebug or {}
local Debug = addon.BarsDebug

-- Reference to FrameState module for safe property storage
local FS = addon.FrameState

local function getProp(frame, key)
    local st = FS.Get(frame)
    return st and st[key] or nil
end

local Utils = addon.BarsUtils
local getFrameScreenOffsets = Utils.getFrameScreenOffsets
local PlayerInCombat = addon.ComponentsUtil.PlayerInCombat

--------------------------------------------------------------------------------
-- Power Bar Debug Trace
--------------------------------------------------------------------------------

local powerBarDebugTraceEnabled = false
local powerBarTraceBuffer = {}
local POWERBAR_TRACE_MAX_LINES = 500 -- Max lines to keep in buffer

addon.SetPowerBarDebugTrace = function(enabled)
    powerBarDebugTraceEnabled = enabled
    if enabled then
        addon:Print("Power bar trace enabled, buffering to log")
        addon:Print("Use '/scoot debug powerbar log' to view, '/scoot debug powerbar clear' to clear")
        table.insert(powerBarTraceBuffer, "=== Trace started at " .. date("%Y-%m-%d %H:%M:%S") .. " ===")
    else
        addon:Print("Power bar trace disabled")
        table.insert(powerBarTraceBuffer, "=== Trace stopped at " .. date("%Y-%m-%d %H:%M:%S") .. " ===")
    end
end

addon.ShowPowerBarTraceLog = function()
    if #powerBarTraceBuffer == 0 then
        addon:Print("Power bar trace buffer is empty")
        return
    end

    local text = table.concat(powerBarTraceBuffer, "\n")
    if addon.DebugShowWindow then
        addon.DebugShowWindow("Power Bar Trace Log (" .. #powerBarTraceBuffer .. " lines)", text)
    else
        addon:Print("Debug window not available. Buffer has " .. #powerBarTraceBuffer .. " lines.")
    end
end

addon.ClearPowerBarTraceLog = function()
    local count = #powerBarTraceBuffer
    powerBarTraceBuffer = {}
    addon:Print("Cleared " .. count .. " lines from power bar trace buffer")
end

function Debug.debugTracePowerBar(message, ...)
    if not powerBarDebugTraceEnabled then return end
    local timestamp = GetTime and string.format("%.3f", GetTime()) or "?"
    local combat = (InCombatLockdown and InCombatLockdown()) and "COMBAT" or "safe"
    local formatted = string.format("[%s][%s] %s", timestamp, combat, message)
    if select("#", ...) > 0 then
        formatted = string.format(formatted, ...)
    end

    table.insert(powerBarTraceBuffer, formatted)

    while #powerBarTraceBuffer > POWERBAR_TRACE_MAX_LINES do
        table.remove(powerBarTraceBuffer, 1)
    end
end

--------------------------------------------------------------------------------
-- Power Bar Position Diagnostics
--------------------------------------------------------------------------------

-- Debug helper:
-- /scoot debug powerbarpos [simulate]
-- Shows current Player ManaBar points + Scoot custom-position state.
function addon.DebugPowerBarPosition(simulateReset)
    if not (addon and addon.DebugShowWindow) then
        return
    end

    local pb =
        _G.PlayerFrame
        and _G.PlayerFrame.PlayerFrameContent
        and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
        and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar

    local lines, push = addon.DebugLines()

    push("InCombatLockdown=" .. tostring((InCombatLockdown and InCombatLockdown()) and true or false))
    push("PlayerInCombat=" .. tostring((PlayerInCombat and PlayerInCombat()) and true or false))
    push("PowerBarFound=" .. tostring(pb ~= nil))

    if not pb then
        addon.DebugShowWindow("Player Power Bar Position", lines)
        return
    end

    local okIgnore, ignoring = false, nil
    if pb.IsIgnoringFramePositionManager then
        okIgnore, ignoring = pcall(pb.IsIgnoringFramePositionManager, pb)
    end
    push("IsIgnoringFramePositionManager=" .. tostring(okIgnore and ignoring or "<n/a>"))

    push("_ScootPowerBarCustomActive=" .. tostring(getProp(pb, "powerBarCustomActive") and true or false))
    push("_ScootPowerBarCustomPosEnabled=" .. tostring(getProp(pb, "powerBarCustomPosEnabled") and true or false))
    push("_ScootPowerBarCustomPosX=" .. tostring(getProp(pb, "powerBarCustomPosX")))
    push("_ScootPowerBarCustomPosY=" .. tostring(getProp(pb, "powerBarCustomPosY")))
    push("_ScootPowerBarCustomPosUnit=" .. tostring(getProp(pb, "powerBarCustomPosUnit")))

    local sx, sy = getFrameScreenOffsets(pb)
    push(string.format("ScreenOffsetFromCenter(px)=%s,%s", tostring(sx), tostring(sy)))

    local function dumpPoints(header)
        push("")
        push(header)
        if not (pb.GetNumPoints and pb.GetPoint) then
            push("<no GetPoint API>")
            return
        end
        local okN, n = pcall(pb.GetNumPoints, pb)
        n = (okN and n) or 0
        push("NumPoints=" .. tostring(n))
        for i = 1, n do
            local ok, point, relTo, relPoint, xOfs, yOfs = pcall(pb.GetPoint, pb, i)
            if ok and point then
                local relName = "<nil>"
                if relTo and relTo.GetName then
                    local okName, nm = pcall(relTo.GetName, relTo)
                    if okName and nm and nm ~= "" then
                        relName = nm
                    else
                        relName = tostring(relTo)
                    end
                else
                    relName = tostring(relTo)
                end
                push(string.format("[%d] %s -> %s (%s) x=%s y=%s", i, tostring(point), tostring(relName), tostring(relPoint), tostring(xOfs), tostring(yOfs)))
            else
                push(string.format("[%d] <error>", i))
            end
        end
    end

    dumpPoints("Points (before)")

    if simulateReset then
        push("")
        push("SimulateReset=true")
        if InCombatLockdown and InCombatLockdown() then
            push("SimulateResetSkipped=InCombatLockdown")
        else
            -- Simulate Blizzard's default reset from PlayerFrame_ToPlayerArt / ToVehicleArt.
            if pb.ClearAllPoints and pb.SetPoint then
                pcall(pb.ClearAllPoints, pb)
                pcall(pb.SetPoint, pb, "TOPLEFT", 85, -61)
            else
                push("SimulateResetSkipped=<no ClearAllPoints/SetPoint>")
            end
        end

        dumpPoints("Points (after simulate)")
    end

    addon.DebugShowWindow("Player Power Bar Position", lines)
end

addon:RegisterDebugCommand({
    name = "powerbarpos", help = "Player power bar anchor points and custom-position state",
    usage = { "powerbarpos [simulate|reset] - also simulate a reset" },
    handler = function(sub) addon.DebugPowerBarPosition(sub == "simulate" or sub == "reset") end,
})

local Commands = addon.Commands

addon:RegisterDebugCommand({
    name = "powerbar", help = "Power bar position trace",
    verbs = Commands.TraceVerbs({
        label = "Power Bar",
        set = addon.SetPowerBarDebugTrace, show = addon.ShowPowerBarTraceLog, clear = addon.ClearPowerBarTraceLog,
    }),
})

return Debug
