-- Scoot.lua - Addon entry point and AceAddon bootstrap
local addonName, addon = ...

LibStub("AceAddon-3.0"):NewAddon(addon, "Scoot", "AceEvent-3.0")
_G.ScootAddon = addon
_G.Scoot = addon

local function PrintScootMessage(text)
    if not text or text == "" then return end
    local prefix = "|cff00ff00[SCOOT]|r"
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s: %s", prefix, text))
    end
end

function addon:Print(message)
    PrintScootMessage(message)
end

-- Developer trace sink. Joins its arguments and routes them through the same
-- chat prefix as Print, so module-level debug helpers do not each reimplement
-- tostring-and-concat. Every call site gates it behind its own debug flag.
function addon.DebugPrint(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    PrintScootMessage(table.concat(parts, " "))
end

-- Open Blizzard's Cooldown Manager / Cooldown Viewer settings UI.
-- Returns true if a target frame was opened, false otherwise.
-- No combat check needed - Blizzard's CDM settings work during combat.
function addon:OpenCooldownManagerSettings()
    local opened = false

    -- Prefer opening the dedicated Cooldown Viewer Settings frame directly
    do
        if _G and _G.CooldownViewerSettings == nil then
            if C_AddOns and C_AddOns.LoadAddOn then
                pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownManager")
                pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownViewer")
            end
        end
        local frame = _G and _G.CooldownViewerSettings
        if frame then
            if frame.TogglePanel then
                opened = pcall(frame.TogglePanel, frame) or opened
            end
            if not opened then
                opened = pcall(ShowUIPanel, frame) or opened
            end
            if not opened and frame.Show then
                opened = pcall(frame.Show, frame) or opened
            end
        end
    end

    -- Fallback: open Settings and search "Cooldown"
    if not opened then
        local S = _G and _G.Settings
        if _G.SettingsPanel and _G.SettingsPanel.Open then pcall(_G.SettingsPanel.Open, _G.SettingsPanel) end
        if S and S.OpenToSearch then pcall(S.OpenToSearch, S, "Cooldown") end
    end

    return opened and true or false
end

SLASH_SCOOT1 = "/scoot"
function SlashCmdList.SCOOT(msg)
    local args = addon.Commands.Parse(msg)
    if #args > 0 and addon.Commands.Dispatch("slash", args) then return end
    if addon.UI and addon.UI.SettingsPanel and addon.UI.SettingsPanel.Toggle then
        addon.UI.SettingsPanel:Toggle()
    end
end

--------------------------------------------------------------------------------
-- /scoot and /scoot debug registrations. Each moves to the file that owns its
-- handler in refactor #32 phase 2; until then they live here, after every owner
-- has loaded.
--------------------------------------------------------------------------------

local Commands = addon.Commands

addon:RegisterDebugCommand({
    name = "slug", help = "SLUG font-flag acceptance probe",
    handler = function() addon.FontStyles.DebugSlugProbe() end,
})

addon:RegisterDebugCommand({
    name = "profiles", help = "profile export and the reload log",
    verbs = {
        { word = "export", usage = 'export ["Profile Name"]', help = "profile as a Lua table; current profile when no name", fn = addon.DebugExportProfile },
        { word = "reload", help = "the reload debug log", fn = addon.DumpReloadDebugLog },
    },
})

-- Read-only dump of one layout's persisted anchor data, straight from
-- C_EditMode.GetLayouts(). For before/after comparison when verifying that
-- cross-machine sessions leave a layout's stored geometry untouched.
addon:RegisterDebugCommand({
    name = "layoutdump", help = "persisted Edit Mode anchors of one layout",
    usage = { 'layoutdump "Layout Name"' },
    handler = function(_, rest)
        local name = rest[1]
        if not name or name == "" then return Commands.USAGE end
        local li = _G.C_EditMode and _G.C_EditMode.GetLayouts and _G.C_EditMode.GetLayouts()
        if not (li and li.layouts) then
            addon:Print("C_EditMode.GetLayouts() returned no data.")
            return
        end
        local found
        for _, layout in ipairs(li.layouts) do
            if layout.layoutName == name then found = layout break end
        end
        if not found then
            local names = {}
            for _, layout in ipairs(li.layouts) do table.insert(names, tostring(layout.layoutName)) end
            addon:Print("Layout not found: " .. tostring(name))
            addon:Print("Available: " .. table.concat(names, ", "))
            return
        end
        local lines = {}
        table.insert(lines, string.format("Layout '%s' (layoutType=%s), %d systems",
            tostring(found.layoutName), tostring(found.layoutType), #(found.systems or {})))
        for _, sys in ipairs(found.systems or {}) do
            local a = sys.anchorInfo or {}
            table.insert(lines, string.format("system=%s index=%s default=%s | %s -> %s/%s (%.2f, %.2f)",
                tostring(sys.system), tostring(sys.systemIndex), tostring(sys.isInDefaultPosition),
                tostring(a.point), tostring(a.relativeTo), tostring(a.relativePoint),
                tonumber(a.offsetX) or 0, tonumber(a.offsetY) or 0))
        end
        addon.DebugShowWindow("Layout dump: " .. name, lines)
    end,
})

addon:RegisterDebugCommand({
    name = "quests", help = "quest log dump",
    handler = function() addon.DebugDumpQuests() end,
})

addon:RegisterDebugCommand({
    name = "consoleport", help = "ConsolePort profile export",
    verbs = {
        { word = "export", help = "copyable ConsolePort profile", fn = addon.DebugExportConsolePortProfile },
    },
})

addon:RegisterDebugCommand({
    name = "editmode", help = "Edit Mode layout export",
    verbs = {
        { word = "export", usage = 'export ["Layout Name"]', help = "raw layout table", fn = addon.DebugExportEditModeLayoutTable },
        { word = "exportstring", usage = 'exportstring ["Layout Name"]', help = "Blizzard share string", fn = addon.DebugExportEditModeLayout },
    },
})

addon:RegisterDebugCommand({
    name = "powerbarpos", help = "Player power bar anchor points and custom-position state",
    usage = { "powerbarpos [simulate|reset] - also simulate a reset" },
    handler = function(sub) addon.DebugPowerBarPosition(sub == "simulate" or sub == "reset") end,
})

addon:RegisterDebugCommand({
    name = "powerbar", help = "Power bar position trace",
    verbs = Commands.TraceVerbs({
        label = "Power Bar",
        set = addon.SetPowerBarDebugTrace, show = addon.ShowPowerBarTraceLog, clear = addon.ClearPowerBarTraceLog,
    }),
})

addon:RegisterDebugCommand({
    name = "trackedbars", aliases = { "tb" }, help = "CDM tracked bars",
    verbs = Commands.TraceVerbs({
        label = "Tracked Bars",
        set = addon.SetTBTrace, show = addon.ShowTBTraceLog, clear = addon.ClearTBTrace,
    }, {
        { word = "state", help = "zero-touch diagnostic (DB, proxy, viewer, children)", fn = function()
            if addon.DebugTBState then addon.DebugTBState() else Commands.NotAvailable("Tracked Bars") end
        end },
        { word = "dump", help = "snapshot of every bar item", fn = function()
            if addon.DumpTBState then addon.DumpTBState() else Commands.NotAvailable("Tracked Bars") end
        end },
    }),
})

addon:RegisterDebugCommand({
    name = "raidframes", aliases = { "rf" }, help = "raid frame state dump",
    handler = function() addon.DebugDumpRaidFrames() end,
})

addon:RegisterDebugCommand({
    name = "sct", help = "world text font and scale log with live CVar state",
    handler = function()
        local state = {}
        for _, name in ipairs({ "WorldTextScale_v2", "WorldTextScale", "WorldTextMinSize" }) do
            local ok, value = pcall(_G.C_CVar.GetCVar, name)
            state[name] = (ok and value ~= nil) and tostring(value) or "<absent>"
        end
        state.resolved = addon.ResolveWorldTextScaleCVar and addon.ResolveWorldTextScaleCVar() or "?"
        addon.LogWorldTextFont("debug sct:cvars", state)
        addon.ShowWorldTextFontLog()
    end,
})

addon:RegisterDebugCommand({
    name = "dm", help = "Native damage meter",
    verbs = {
        { word = "state", help = "zero-touch diagnostic", fn = function()
            if addon.DebugDMState then addon.DebugDMState() else Commands.NotAvailable("Damage Meter") end
        end },
        { word = "export", usage = "export [overall|current|expired]", help = "session export", fn = addon.DebugExportDamageMeters },
        { word = "frames", help = "window and overlay frames", fn = function()
            if addon.DebugDMFrames then addon.DebugDMFrames() else Commands.NotAvailable("Damage Meter") end
        end },
        { word = "trace", usage = "trace <on|off>", help = "buffer the error log into the frames dump", fn = function(token)
            token = string.lower(token or "")
            if token ~= "on" and token ~= "off" then return Commands.USAGE end
            if addon.SetDMDebug then addon.SetDMDebug(token == "on") else Commands.NotAvailable("Damage Meter") end
        end },
    },
})

addon:RegisterDebugCommand({
    name = "dj", help = "Dungeon Journal season snapshot and marks",
    handler = function()
        local DJ = addon.DungeonJournal
        local lines = {}
        local function push(s) lines[#lines + 1] = s end
        push(string.format("DJ enabled: %s", tostring(DJ.IsEnabled and DJ.IsEnabled())))
        local ej = _G.EncounterJournal
        local instanceID = ej and rawget(ej, "instanceID") or nil
        push(string.format("EJ.instanceID: %s", tostring(instanceID)))
        if type(instanceID) == "number" and EJ_GetInstanceInfo then
            local ok, name, _, _, _, _, _, dungeonAreaMapID = pcall(EJ_GetInstanceInfo, instanceID)
            if ok then
                push(string.format("  name=%s  dungeonAreaMapID=%s", tostring(name), tostring(dungeonAreaMapID)))
            end
            push(string.format("  IsCurrentSeasonInstance: %s",
                tostring(DJ.IsCurrentSeasonInstance and DJ.IsCurrentSeasonInstance(instanceID))))
        end
        local s = DJ._SeasonDebug and DJ._SeasonDebug() or {}
        push(string.format("Snapshot: have=%s  requested=%s", tostring(s.haveSnapshot), tostring(s.requestedOnce)))
        local nameCount = 0
        for n in pairs(s.seasonNames or {}) do
            nameCount = nameCount + 1
            push(string.format("  season name: %s", n))
        end
        push(string.format("  total season names: %d", nameCount))
        push(string.format("Marks on this character: %d", (DJ.CountMarks and DJ.CountMarks()) or 0))
        addon.DebugShowWindow("Dungeon Journal", lines)
    end,
})

--------------------------------------------------------------------------------
-- /scoot registrations (the slash scope)
--------------------------------------------------------------------------------

addon:RegisterSlashCommand({
    name = "debugmenu", help = "toggle the Debug Menu page in the settings panel",
    handler = function()
        if not (addon.db and addon.db.profile) then
            addon:Print("Profile not loaded yet. Try again after login completes.")
            return
        end
        addon.db.profile.debugMenuEnabled = not addon.db.profile.debugMenuEnabled
        local status = addon.db.profile.debugMenuEnabled and "ENABLED" or "DISABLED"
        addon:Print("Debug menu " .. status .. ". Reopen settings to see changes.")
    end,
})

addon:RegisterSlashCommand({
    name = "del", aliases = { "delete" }, help = "delete an Edit Mode layout by name",
    usage = { 'del "Layout Name"' },
    handler = function(_, rest)
        local target = rest[1]
        if not target or target == "" then return Commands.USAGE end
        if InCombatLockdown and InCombatLockdown() then addon:Print("Cannot delete during combat.") return end
        local LEO = LibStub and LibStub("LibEditModeOverride-1.0")
        if not (LEO and LEO.IsReady and LEO:IsReady()) then addon:Print("Edit Mode not ready.") return end
        if LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
        if not (LEO.DoesLayoutExist and LEO:DoesLayoutExist(target)) then addon:Print("Layout not found: "..target) return end
        local ok, err = pcall(LEO.DeleteLayout, LEO, target)
        if not ok then addon:Print("Delete failed: "..tostring(err)) return end
        if LEO.SaveOnly then pcall(LEO.SaveOnly, LEO) end
        if LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
        if LEO.DoesLayoutExist and LEO:DoesLayoutExist(target) then
            addon:Print("Delete did not persist (still exists): "..target)
        else
            addon:Print("Deleted layout: "..target)
        end
    end,
})

addon:RegisterSlashCommand({
    name = "attr", help = "dump the inspected Table Inspector table or Frame Stack frame",
    handler = function()
        if not addon.DumpTableAttributes() then
            addon:Print("No Table Inspector window or highlight frame found to dump.")
        end
    end,
})

addon:RegisterSlashCommand({
    name = "taint", help = "taint debugging",
    usage = { "taint <on|off|log|clear|status>" },
    handler = function(_, rest) addon.TaintDebug.HandleSlashCommand(rest) end,
})

addon:RegisterSlashCommand({
    name = "widget", help = "widget component",
    verbs = {
        { word = "reset", help = "reset the widget position", fn = function()
            addon.Widget:ResetPosition()
            addon:Print("Widget position reset.")
        end },
    },
})

addon:RegisterSlashCommand({
    name = "copy", help = "copy an Edit Mode layout under a new name",
    usage = { 'copy "Source Name" "New Name"' },
    handler = function(_, rest)
        local src, dest = rest[1], rest[2]
        if not src or not dest then return Commands.USAGE end
        if InCombatLockdown and InCombatLockdown() then addon:Print("Cannot copy during combat.") return end
        C_AddOns.LoadAddOn("Blizzard_EditMode")
        local layouts = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
        if not (EditModeManagerFrame and layouts and layouts.layouts) then addon:Print("Edit Mode not ready.") return end
        local source
        for _, layout in ipairs(layouts.layouts) do
            if layout.layoutName == src then source = CopyTable(layout) break end
        end
        if not source then addon:Print("Source layout not found: "..src) return end
        if C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(dest) then addon:Print("Invalid new name.") return end
        if EditModeManagerFrame.MakeNewLayout then
            EditModeManagerFrame:MakeNewLayout(source, source.layoutType or Enum.EditModeLayoutType.Account, dest, false)
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            addon:Print("Copied layout '"..src.."' -> '"..dest.."'")
        else
            addon:Print("Copy failed: manager unavailable.")
        end
    end,
})

-- /cdm (optional, gated by profile setting)
SLASH_SCOOTCDM1 = "/cdm"
function SlashCmdList.SCOOTCDM(msg, editBox)
    local profile = addon and addon.db and addon.db.profile
    local enabled = profile and profile.cdmQoL and profile.cdmQoL.enableSlashCDM
    if not enabled then
        if addon and addon.Print then
            addon:Print("Enable /cdm in Scoot → Cooldown Manager → Quality of Life.")
        end
        return
    end
    addon:OpenCooldownManagerSettings()
end

-- /dmshow (toggle damage meter visibility, gated by per-version QoL setting)
SLASH_SCOOTDMSHOW1 = "/dmshow"
function SlashCmdList.SCOOTDMSHOW(msg, editBox)
    if not (addon and addon.IsModuleEnabled) then return end

    if not addon:IsModuleEnabled("damageMeter") then
        addon:Print("Damage Meter module is disabled.")
        return
    end

    local isY = addon:IsModuleEnabled("damageMeter", "damageMeterV2")
    local compId = isY and "damageMeterV2" or "damageMeter"
    local comp = addon.Components and addon.Components[compId]
    local enabled = comp and comp.db and comp.db.enableSlashDM
    if not enabled then
        addon:Print("Enable /dm commands in Scoot \226\134\146 Damage Meter \226\134\146 Quality of Life.")
        return
    end

    if isY then
        if addon.DamageMetersY and addon.DamageMetersY._SlashToggleShow then
            addon.DamageMetersY._SlashToggleShow()
        end
    else
        if addon.DamageMetersX and addon.DamageMetersX._SlashToggleShow then
            addon.DamageMetersX._SlashToggleShow()
        end
    end
end

-- /dmreset (reset all damage meter data, gated by per-version QoL setting)
SLASH_SCOOTDMRESET1 = "/dmreset"
function SlashCmdList.SCOOTDMRESET(msg, editBox)
    if not (addon and addon.IsModuleEnabled) then return end

    if not addon:IsModuleEnabled("damageMeter") then
        addon:Print("Damage Meter module is disabled.")
        return
    end

    local isY = addon:IsModuleEnabled("damageMeter", "damageMeterV2")
    local compId = isY and "damageMeterV2" or "damageMeter"
    local comp = addon.Components and addon.Components[compId]
    local enabled = comp and comp.db and comp.db.enableSlashDM
    if not enabled then
        addon:Print("Enable /dm commands in Scoot \226\134\146 Damage Meter \226\134\146 Quality of Life.")
        return
    end

    if isY then
        if addon.DamageMetersY and addon.DamageMetersY._SlashReset then
            addon.DamageMetersY._SlashReset()
        end
    else
        if addon.DamageMetersX and addon.DamageMetersX._SlashReset then
            addon.DamageMetersX._SlashReset()
        end
    end
end


-- PLAYER_TARGET_CHANGED is handled in core/init.lua — do not duplicate here.
