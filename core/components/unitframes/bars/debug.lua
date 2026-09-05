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

    local pb = addon.Frames.resolvePowerBar(nil, "Player")

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


--------------------------------------------------------------------------------
-- Group Frames Diagnostic: /scoot debug raidframes
-- Captures the exact state of all raid and party frames to identify why
-- they're invisible.
--------------------------------------------------------------------------------
function addon.DebugDumpRaidFrames()
    local getState = addon.BarsRaidFrames and addon.BarsRaidFrames._getState
    local lines, add = addon.DebugLines()

    add("=== Raid Frames Diagnostic ===")
    add(string.format("Time: %s", date("%Y-%m-%d %H:%M:%S")))
    add(string.format("InRaid: %s", tostring(IsInRaid and IsInRaid())))
    add(string.format("InGroup: %s", tostring(IsInGroup and IsInGroup())))
    add(string.format("InCombatLockdown: %s", tostring(InCombatLockdown and InCombatLockdown())))

    -- Edit Mode guard state
    local emGuard = "N/A"
    if addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening then
        emGuard = tostring(addon.EditMode.IsEditModeActiveOrOpening())
    end
    add(string.format("isEditModeActive(): %s", emGuard))

    -- Check the live Blizzard Edit Mode state
    local mgr = _G.EditModeManagerFrame
    if mgr then
        local ok1, active = pcall(function() return mgr.editModeActive end)
        local ok2, shown = pcall(mgr.IsShown, mgr)
        add(string.format("EditModeManagerFrame.editModeActive: %s (ok=%s)",
            tostring(active), tostring(ok1)))
        add(string.format("EditModeManagerFrame:IsShown(): %s (ok=%s)",
            tostring(shown), tostring(ok2)))
    else
        add("EditModeManagerFrame: nil")
    end
    add(string.format("_openingEditMode: %s", tostring(addon.EditMode and addon.EditMode._openingEditMode)))
    add(string.format("_exitingEditMode: %s", tostring(addon.EditMode and addon.EditMode._exitingEditMode)))

    -- DB config check
    local db = addon and addon.db and addon.db.profile
    local groupFrames = db and rawget(db, "groupFrames") or nil
    local cfg = groupFrames and rawget(groupFrames, "raid") or nil
    if cfg then
        add(string.format("\nhealthBarTexture: %s", tostring(cfg.healthBarTexture)))
        add(string.format("healthBarColorMode: %s", tostring(cfg.healthBarColorMode)))
        add(string.format("healthBarBackgroundTexture: %s", tostring(cfg.healthBarBackgroundTexture)))
        add(string.format("healthBarBackgroundColorMode: %s", tostring(cfg.healthBarBackgroundColorMode)))
        local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default")
                       or (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
        add(string.format("hasCustom (fg): %s", tostring(hasCustom)))
    else
        add("\ncfg (db.groupFrames.raid): NIL — overlays will not be applied")
    end

    -- Container state
    local container = _G.CompactRaidFrameContainer
    if container then
        local okS, shown = pcall(container.IsShown, container)
        local okV, visible = pcall(container.IsVisible, container)
        add(string.format("\nCompactRaidFrameContainer: exists, IsShown=%s, IsVisible=%s",
            tostring(shown), tostring(visible)))
    else
        add("\nCompactRaidFrameContainer: nil (does not exist)")
    end

    -- Sample frames
    add("\n--- Combined Layout (CompactRaidFrame1..40) ---")
    local combinedExists, combinedShown = 0, 0
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            combinedExists = combinedExists + 1
            local okS, shown = pcall(frame.IsShown, frame)
            if okS and shown then combinedShown = combinedShown + 1 end
        end
    end
    add(string.format("Exist: %d, Shown: %d", combinedExists, combinedShown))

    add("\n--- Group Layout (CompactRaidGroup*Member*) ---")
    local groupExists, groupShown = 0, 0
    for g = 1, 8 do
        for m = 1, 5 do
            local frame = _G["CompactRaidGroup" .. g .. "Member" .. m]
            if frame then
                groupExists = groupExists + 1
                local okS, shown = pcall(frame.IsShown, frame)
                if okS and shown then groupShown = groupShown + 1 end
            end
        end
    end
    add(string.format("Exist: %d, Shown: %d", groupExists, groupShown))

    -- Detailed state for first 5 visible frames
    add("\n--- Detailed Frame State (first 5 shown frames) ---")
    local detailed = 0
    local function detailFrame(frameName)
        if detailed >= 5 then return end
        local frame = _G[frameName]
        if not frame then return end
        local okS, shown = pcall(frame.IsShown, frame)
        if not (okS and shown) then return end
        detailed = detailed + 1
        add(string.format("\n[%s]", frameName))
        -- Unit
        local okU, unit = pcall(function() return frame.displayedUnit or frame.unit end)
        add(string.format("  unit: %s (ok=%s)", tostring(unit), tostring(okU)))
        -- HealthBar
        local bar = frame.healthBar
        if not bar then
            add("  healthBar: nil")
            return
        end
        local okBS, barShown = pcall(bar.IsShown, bar)
        local okBV, barVisible = pcall(bar.IsVisible, bar)
        add(string.format("  healthBar: IsShown=%s, IsVisible=%s", tostring(barShown), tostring(barVisible)))
        -- Fill texture
        local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        if fill then
            local okA, alpha = pcall(fill.GetAlpha, fill)
            local okT, tex = pcall(fill.GetTexture, fill)
            add(string.format("  fill: alpha=%s, tex=%s", tostring(alpha), tostring(tex)))
        else
            add("  fill: nil (no status bar texture)")
        end
        -- Overlay state
        local state = getState and getState(bar)
        if state then
            local overlay = state.healthOverlay
            add(string.format("  overlayActive: %s", tostring(state.overlayActive)))
            add(string.format("  healthOverlay: %s", overlay and "exists" or "nil"))
            if overlay then
                local okOS, ovShown = pcall(overlay.IsShown, overlay)
                local okOV, ovVisible = pcall(overlay.IsVisible, overlay)
                local okOA, ovAlpha = pcall(overlay.GetAlpha, overlay)
                local okOT, ovTex = pcall(overlay.GetTexture, overlay)
                add(string.format("  overlay IsShown=%s, IsVisible=%s, alpha=%s, tex=%s",
                    tostring(ovShown), tostring(ovVisible), tostring(ovAlpha), tostring(ovTex)))
                -- Check if overlay has valid anchor points
                local okP, p1 = pcall(overlay.GetNumPoints, overlay)
                add(string.format("  overlay numPoints=%s", tostring(p1)))
            end
            add(string.format("  fingerprint: %s", state.lastAppliedFingerprint and "set" or "nil"))
            add(string.format("  overlayHooksInstalled: %s", tostring(state.overlayHooksInstalled)))
            add(string.format("  textureSwapHooked: %s", tostring(state.textureSwapHooked)))
            -- Frame-level topology snapshot (parent / bar / Blizzard's dispelDebuffFrames icon container).
            local okBL, barLvl = pcall(bar.GetFrameLevel, bar)
            local okPL, parLvl = pcall(frame.GetFrameLevel, frame)
            local dDF = frame.dispelDebuffFrames
            local ddfLvl, ddfParLvl
            if dDF and dDF[1] then
                local okD, v = pcall(dDF[1].GetFrameLevel, dDF[1])
                if okD then ddfLvl = v end
                local pp = dDF[1].GetParent and dDF[1]:GetParent()
                if pp then
                    local okP, v2 = pcall(pp.GetFrameLevel, pp)
                    if okP then ddfParLvl = v2 end
                end
            end
            add(string.format("  ctx: parLvl=%s bar:lvl=%s dDF[1]:lvl=%s dDF[1].parent:lvl=%s",
                tostring(parLvl), tostring(barLvl), tostring(ddfLvl), tostring(ddfParLvl)))
        else
            add("  RaidFrameState: nil (no state for this bar)")
        end
    end

    for i = 1, 40 do detailFrame("CompactRaidFrame" .. i) end
    for g = 1, 8 do
        for m = 1, 5 do detailFrame("CompactRaidGroup" .. g .. "Member" .. m) end
    end

    if detailed == 0 then
        add("\n  (No shown frames found — checking first 5 existing frames instead)")
        detailed = 0
        local function detailAnyFrame(frameName)
            if detailed >= 5 then return end
            local frame = _G[frameName]
            if not frame then return end
            detailed = detailed + 1
            add(string.format("\n[%s] (exists but not shown)", frameName))
            local okS, shown = pcall(frame.IsShown, frame)
            local okV, visible = pcall(frame.IsVisible, frame)
            add(string.format("  IsShown=%s, IsVisible=%s", tostring(shown), tostring(visible)))
            local okU, unit = pcall(function() return frame.displayedUnit or frame.unit end)
            add(string.format("  unit: %s", tostring(unit)))
            local bar = frame.healthBar
            if bar then
                local okBS, barShown = pcall(bar.IsShown, bar)
                add(string.format("  healthBar: IsShown=%s", tostring(barShown)))
            else
                add("  healthBar: nil")
            end
        end
        for i = 1, 40 do detailAnyFrame("CompactRaidFrame" .. i) end
        for g = 1, 8 do
            for m = 1, 5 do detailAnyFrame("CompactRaidGroup" .. g .. "Member" .. m) end
        end
    end

    add("\n--- Hooks ---")
    add(string.format("_RaidFrameHooksInstalled: %s", tostring(addon._RaidFrameHooksInstalled)))
    add(string.format("_RaidFrameIntegrityCheckInstalled: %s", tostring(addon._RaidFrameIntegrityCheckInstalled)))

    -- Party frames inspection
    add("\n=== Party Frames ===")
    local partyContainer = _G.CompactPartyFrame
    if partyContainer then
        local okS, shown = pcall(partyContainer.IsShown, partyContainer)
        local okV, visible = pcall(partyContainer.IsVisible, partyContainer)
        add(string.format("CompactPartyFrame: exists, IsShown=%s, IsVisible=%s",
            tostring(shown), tostring(visible)))
    else
        add("CompactPartyFrame: nil")
    end

    -- Helper: secret-safe tostring. Any value that issecretvalue() flags is
    -- replaced with "<secret>" so table.concat doesn't blow up later.
    local function safeStr(v)
        if v == nil then return "nil" end
        if _G.issecretvalue and _G.issecretvalue(v) then return "<secret>" end
        local ok, s = pcall(tostring, v)
        if not ok then return "<tostring-fail>" end
        if _G.issecretvalue and _G.issecretvalue(s) then return "<secret>" end
        return s
    end

    -- Walk Compact party member frames + their health overlay state
    local partyState = addon.BarsPartyFrames and addon.BarsPartyFrames._getState
    add("\n--- Party member frames ---")
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            local okS, shown = pcall(frame.IsShown, frame)
            local okU, unit = pcall(function() return frame.displayedUnit or frame.unit end)
            add(string.format("[%s] shown=%s unit=%s",
                "CompactPartyFrameMember" .. i, safeStr(shown), safeStr(unit)))
            local bar = frame.healthBar
            if bar and partyState then
                local st = partyState(bar)
                if st and st.healthOverlay then
                    local okHL, layer, sub = pcall(st.healthOverlay.GetDrawLayer, st.healthOverlay)
                    local okHS, hShown = pcall(st.healthOverlay.IsShown, st.healthOverlay)
                    add(string.format("  healthOverlay: layer=%s sub=%s shown=%s overlayActive=%s",
                        safeStr(layer), safeStr(sub), safeStr(hShown), safeStr(st.overlayActive)))
                else
                    add("  healthOverlay: nil")
                end
            end
        end
    end

    add("\n--- Party Hooks ---")
    add(string.format("_PartyFrameHooksInstalled: %s", tostring(addon._PartyFrameHooksInstalled)))

    addon.DebugShowWindow("Group Frames Diagnostic", lines)
end

addon:RegisterDebugCommand({
    name = "raidframes", aliases = { "rf" }, help = "raid frame state dump",
    handler = function() addon.DebugDumpRaidFrames() end,
})

return Debug
