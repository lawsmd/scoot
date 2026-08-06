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
function SlashCmdList.SCOOT(msg, editBox)
    local function trim(s)
        if type(s) ~= "string" then return "" end
        return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    local function parseQuotedArgs(s)
        local args = {}
        s = s or ""
        local i = 1
        while i <= #s do
            local c = s:sub(i, i)
            if c == '"' then
                local j = i + 1
                while j <= #s and s:sub(j, j) ~= '"' do j = j + 1 end
                table.insert(args, s:sub(i + 1, j - 1))
                i = (j < #s) and (j + 2) or (j + 1)
            else
                local j = i
                while j <= #s and not s:sub(j, j):match("%s") do j = j + 1 end
                table.insert(args, s:sub(i, j - 1))
                i = j + 1
            end
        end
        return args
    end

    msg = trim(msg)
    if msg == "" then
        if addon.UI and addon.UI.SettingsPanel and addon.UI.SettingsPanel.Toggle then
            addon.UI.SettingsPanel:Toggle()
        end
        return
    end

    local args = parseQuotedArgs(msg)
    local cmd = string.lower(args[1] or "")

    -- /scoot debugmenu
    if cmd == "debugmenu" then
        if not (addon.db and addon.db.profile) then
            addon:Print("Profile not loaded yet. Try again after login completes.")
            return
        end
        addon.db.profile.debugMenuEnabled = not addon.db.profile.debugMenuEnabled
        local status = addon.db.profile.debugMenuEnabled and "ENABLED" or "DISABLED"
        addon:Print("Debug menu " .. status .. ". Reopen settings to see changes.")
        return
    end

    -- /scoot del "Layout Name"
    if cmd == "del" or cmd == "delete" then
        local target = args[2]
        if not target or target == "" then addon:Print("Usage: /scoot del \"Layout Name\"") return end
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
        return
    end

    -- /scoot debug <target>
    -- /scoot debug profiles export ["Profile Name"]
    if cmd == "debug" then
        local sub1 = string.lower(args[2] or "")
        local sub2 = string.lower(args[3] or "")

        if sub1 == "" then
            addon:Print("Usage:")
            addon:Print("  /scoot debug <player|target|focus|pet|ab1..ab8|essential|utility|micro|stance|buffs|debuffs|offscreen|powerbarpos|dim|trackedbars|classauras|quests|<FrameName>>")
            addon:Print("  /scoot debug profiles export [\"Profile Name\"]  |  reload")
            addon:Print("  /scoot debug consoleport export")
            addon:Print("  /scoot debug cdmlayers")
            addon:Print("  /scoot debug hover [seconds]  -- what is eating the mouse at the cursor")
            addon:Print("  /scoot debug dm export [overall|current|expired]")
            addon:Print("  /scoot debug dm frames")
            addon:Print("  /scoot debug dm trace <on|off>")
            addon:Print("  /scoot debug dmY cvar")
            addon:Print("  /scoot debug dmY api")
            addon:Print("  /scoot debug dmY fields")
            addon:Print("  /scoot debug dmY drilldown")
            addon:Print("  /scoot debug dmY drilldata")
            addon:Print("  /scoot debug dmY multicol")
            addon:Print("  /scoot debug dmY abbrev")
            addon:Print("  /scoot debug dmY colprobe")
            addon:Print("  /scoot debug widget <spawnchild|releaseall|state>")
            addon:Print("  /scoot debug inspect <state|cache>")
            addon:Print("  /scoot debug nametext [size|lines|range|fallback|mode|font|case|caseprobe|sample|gradient|chrome|margin|slices|class|treatment|scan|lengthprobe|fitprobe|autofit|report]")
            addon:Print("  /scoot debug castz [player|pet|target|focus|boss1..5]")
            addon:Print("  /scoot debug castz petevents   (toggle pet cast-event watch)")
            addon:Print("  /scoot debug castz endorder [unit]  (toggle cast-end event order watch)")
            addon:Print("  /scoot debug castz fit         (shrink-to-fit state of each live bar)")
            addon:Print("  /scoot debug repcolor [watch]   (ReputationColor banner trace)")
            return
        end

        if sub1 == "widget" then
            if sub2 == "spawnchild" then
                if addon.DebugWidgetSpawnChild then
                    addon.DebugWidgetSpawnChild()
                else
                    addon:Print("Widget debug not loaded.")
                end
                return
            end
            if sub2 == "releaseall" then
                if addon.DebugWidgetReleaseAll then
                    addon.DebugWidgetReleaseAll()
                else
                    addon:Print("Widget debug not loaded.")
                end
                return
            end
            if sub2 == "state" or sub2 == "" then
                if addon.DebugWidgetState then
                    addon.DebugWidgetState()
                else
                    addon:Print("Widget debug not loaded.")
                end
                return
            end
            addon:Print("Usage: /scoot debug widget <spawnchild|releaseall|state>")
            return
        end

        if sub1 == "inspect" then
            if sub2 == "cache" then
                if addon.DebugInspectCache then
                    addon.DebugInspectCache()
                else
                    addon:Print("Inspect debug not loaded.")
                end
                return
            end
            if sub2 == "state" or sub2 == "" then
                if addon.DebugInspectState then
                    addon.DebugInspectState()
                else
                    addon:Print("Inspect debug not loaded.")
                end
                return
            end
            addon:Print("Usage: /scoot debug inspect <state|cache>")
            return
        end

        if sub1 == "profiles" then
            if sub2 == "export" then
                local name = args[4]
                if addon.DebugExportProfile then
                    addon.DebugExportProfile(name)
                else
                    addon:Print("Profile export not available (debug module missing).")
                end
                return
            end
            if sub2 == "reload" then
                if addon.DumpReloadDebugLog then
                    addon.DumpReloadDebugLog()
                else
                    addon:Print("Reload debug log not available.")
                end
                return
            end
            addon:Print("Usage: /scoot debug profiles export [\"Profile Name\"]")
            addon:Print("       /scoot debug profiles reload")
            return
        end

        if sub1 == "quests" then
            if addon.DebugDumpQuests then
                addon.DebugDumpQuests()
            else
                addon:Print("Quest debug not available.")
            end
            return
        end

        if sub1 == "consoleport" then
            if sub2 == "export" then
                if addon.DebugExportConsolePortProfile then
                    addon.DebugExportConsolePortProfile()
                else
                    addon:Print("ConsolePort export helper not available (debug module missing).")
                end
                return
            end
            addon:Print("Usage: /scoot debug consoleport export")
            return
        end

        -- /scoot debug editmode export ["Layout Name"]  (raw table)
        -- /scoot debug editmode exportstring ["Layout Name"] (Blizzard Share string)
        if sub1 == "editmode" then
            if sub2 == "export" then
                local name = args[4]
                if addon.DebugExportEditModeLayoutTable then
                    addon.DebugExportEditModeLayoutTable(name)
                else
                    addon:Print("Edit Mode export helper not available (debug module missing).")
                end
                return
            end
            if sub2 == "exportstring" then
                local name = args[4]
                if addon.DebugExportEditModeLayout then
                    addon.DebugExportEditModeLayout(name)
                else
                    addon:Print("Edit Mode export helper not available (debug module missing).")
                end
                return
            end
            addon:Print("Usage: /scoot debug editmode export [\"Layout Name\"]")
            addon:Print("       /scoot debug editmode exportstring [\"Layout Name\"]")
            return
        end

        -- /scoot debug offscreen
        if sub1 == "offscreen" then
            if addon.DebugOffscreenUnlockDump then
                addon.DebugOffscreenUnlockDump()
            else
                addon:Print("Off-screen debug not available (debug module missing).")
            end
            return
        end

        -- /scoot debug powerbarpos [simulate]
        if sub1 == "powerbarpos" then
            local simulate = (sub2 == "simulate" or sub2 == "reset")
            if addon.DebugPowerBarPosition then
                addon.DebugPowerBarPosition(simulate)
            else
                addon:Print("Power Bar position debug not available (bars module missing).")
            end
            return
        end

        -- /scoot debug powerbar <trace|log|clear>
        -- Debug tracing for Power Bar positioning issues
        if sub1 == "powerbar" then
            if sub2 == "trace" then
                local toggle = args[4]
                if toggle == "on" then
                    if addon.SetPowerBarDebugTrace then
                        addon.SetPowerBarDebugTrace(true)
                    else
                        addon:Print("Power Bar debug trace not available (bars module missing).")
                    end
                elseif toggle == "off" then
                    if addon.SetPowerBarDebugTrace then
                        addon.SetPowerBarDebugTrace(false)
                    else
                        addon:Print("Power Bar debug trace not available (bars module missing).")
                    end
                else
                    addon:Print("Usage: /scoot debug powerbar trace <on|off>")
                end
            elseif sub2 == "log" then
                if addon.ShowPowerBarTraceLog then
                    addon.ShowPowerBarTraceLog()
                else
                    addon:Print("Power Bar trace log not available (bars module missing).")
                end
            elseif sub2 == "clear" then
                if addon.ClearPowerBarTraceLog then
                    addon.ClearPowerBarTraceLog()
                else
                    addon:Print("Power Bar trace clear not available (bars module missing).")
                end
            else
                addon:Print("Usage: /scoot debug powerbar <trace|log|clear>")
                addon:Print("  trace on  - Start tracing Power Bar position changes")
                addon:Print("  trace off - Stop tracing")
                addon:Print("  log       - Show trace buffer in copyable window")
                addon:Print("  clear     - Clear the trace buffer")
            end
            return
        end


        -- /scoot debug trackedbars <trace|log|clear|dump>
        if sub1 == "trackedbars" or sub1 == "tb" then
            if sub2 == "state" then
                if addon.DebugTBState then
                    addon.DebugTBState()
                else
                    addon:Print("TB state debug not available (trackedbars module missing).")
                end
                return
            end
            if sub2 == "trace" then
                local toggle = args[4]
                if toggle == "on" then
                    if addon.SetTBTrace then addon.SetTBTrace(true)
                    else addon:Print("TB trace not available (trackedbars module missing).") end
                elseif toggle == "off" then
                    if addon.SetTBTrace then addon.SetTBTrace(false)
                    else addon:Print("TB trace not available (trackedbars module missing).") end
                else
                    addon:Print("Usage: /scoot debug trackedbars trace <on|off>")
                end
            elseif sub2 == "log" then
                if addon.ShowTBTraceLog then addon.ShowTBTraceLog()
                else addon:Print("TB trace log not available.") end
            elseif sub2 == "clear" then
                if addon.ClearTBTrace then addon.ClearTBTrace()
                else addon:Print("TB trace clear not available.") end
            elseif sub2 == "dump" then
                if addon.DumpTBState then addon.DumpTBState()
                else addon:Print("TB dump not available.") end
            else
                addon:Print("Usage: /scoot debug trackedbars <state|trace|log|clear|dump>")
                addon:Print("  state     - Zero-touch diagnostic (DB, proxy, viewer, children)")
                addon:Print("  trace on  - Start tracing bar lifecycle events")
                addon:Print("  trace off - Stop tracing")
                addon:Print("  log       - Show trace buffer in copyable window")
                addon:Print("  clear     - Clear the trace buffer")
                addon:Print("  dump      - Snapshot current state of all bar items")
            end
            return
        end

        -- /scoot debug raidframes
        if sub1 == "raidframes" or sub1 == "rf" then
            if addon.DebugDumpRaidFrames then
                addon.DebugDumpRaidFrames()
            else
                addon:Print("Raid Frames debug not available (raidframes module missing).")
            end
            return
        end

        -- /scoot debug cdmlayers
        if sub1 == "cdmlayers" then
            if addon.DebugCDMLayers then
                addon.DebugCDMLayers()
            else
                addon:Print("CDM layers debug not available.")
            end
            return
        end

        -- /scoot debug hover [seconds]
        if sub1 == "hover" then
            if addon.DebugHover then
                addon.DebugHover(sub2)
            else
                addon:Print("Hover probe not available.")
            end
            return
        end

        -- /scoot debug classauras
        if sub1 == "classauras" or sub1 == "ca" then
            if addon.DebugDumpClassAuras then
                addon.DebugDumpClassAuras()
            else
                addon:Print("Class Auras debug not available (debug module missing).")
            end
            return
        end

        -- /scoot debug altertime
        if sub1 == "altertime" or sub1 == "at" then
            if addon.DebugAlterTimeHealth then
                addon.DebugAlterTimeHealth()
            else
                addon:Print("Alter Time debug not available (debug module missing).")
            end
            return
        end

        -- /scoot debug dm export [overall|current|expired]
        -- /scoot debug dm frames
        -- /scoot debug dm trace <on|off>
        if sub1 == "dm" then
            if sub2 == "export" then
                local sessionArg = args[4]
                if addon.DebugExportDamageMeters then
                    addon.DebugExportDamageMeters(sessionArg)
                else
                    addon:Print("Damage Meter export not available (debug module missing).")
                end
                return
            end
            if sub2 == "state" then
                if addon.DebugDMState then
                    addon.DebugDMState()
                else
                    addon:Print("DM state debug not available (damage meter module missing).")
                end
                return
            end
            if sub2 == "frames" then
                if addon.DebugDMFrames then
                    addon.DebugDMFrames()
                else
                    addon:Print("DM frame debug not available (damage meter module missing).")
                end
                return
            end
            if sub2 == "trace" then
                local toggle = args[4]
                if toggle == "on" then
                    if addon.SetDMDebug then addon.SetDMDebug(true)
                    else addon:Print("DM debug not available.") end
                elseif toggle == "off" then
                    if addon.SetDMDebug then addon.SetDMDebug(false)
                    else addon:Print("DM debug not available.") end
                else
                    addon:Print("Usage: /scoot debug dm trace <on|off>")
                end
                return
            end
            addon:Print("Usage: /scoot debug dm state")
            addon:Print("       /scoot debug dm export [overall|current|expired]")
            addon:Print("       /scoot debug dm frames")
            addon:Print("       /scoot debug dm trace <on|off>")
            return
        end

        -- /scoot debug rosteroverlay
        if sub1 == "rosteroverlay" or sub1 == "roster" then
            if sub2 == "rows" then
                if addon.DebugRosterOverlayRows then addon.DebugRosterOverlayRows()
                else addon:Print("Roster overlay debug not available.") end
                return
            end
            if addon.DebugRosterOverlay then addon.DebugRosterOverlay()
            else addon:Print("Roster overlay debug not available.") end
            return
        end

        -- /scoot debug castz [unit] - Cast Bar Z phase 0 API probe
        -- /scoot debug castz petevents
        if sub1 == "castz" then
            -- "petevents", not "pet" — "pet" is a valid unit to probe.
            if sub2 == "petevents" then
                if addon.DebugCastZPet then addon.DebugCastZPet()
                else addon:Print("Cast Bar Z debug not available.") end
                return
            end
            if sub2 == "endorder" then
                if addon.DebugCastZEndOrder then addon.DebugCastZEndOrder(args[4])
                else addon:Print("Cast Bar Z debug not available.") end
                return
            end
            if sub2 == "fit" then
                if addon.DebugCastZFit then addon.DebugCastZFit()
                else addon:Print("Cast Bar Z debug not available.") end
                return
            end
            if sub2 == "empower" then
                if addon.DebugCastZEmpower then addon.DebugCastZEmpower(args[4])
                else addon:Print("Cast Bar Z debug not available.") end
                return
            end
            if sub2 == "time" then
                if addon.DebugCastZTime then addon.DebugCastZTime(args[4])
                else addon:Print("Cast Bar Z debug not available.") end
                return
            end
            if addon.DebugCastZProbe then addon.DebugCastZProbe(sub2)
            else addon:Print("Cast Bar Z debug not available.") end
            return
        end

        -- /scoot debug repcolor [watch] - ReputationColor banner lifecycle trace
        if sub1 == "repcolor" then
            if addon.DebugRepColor then addon.DebugRepColor(sub2)
            else addon:Print("RepColor debug not available.") end
            return
        end

        -- /scoot debug dmY cvar
        -- /scoot debug dmY api
        if sub1 == "dmy" then
            if sub2 == "cvar" then
                if addon.DebugDMYCVar then addon.DebugDMYCVar()
                else addon:Print("DMY debug not available.") end
                return
            end
            if sub2 == "api" then
                if addon.DebugDMYAPI then addon.DebugDMYAPI()
                else addon:Print("DMY debug not available.") end
                return
            end
            if sub2 == "trace" then
                if addon.DebugDMYTrace then addon.DebugDMYTrace()
                else addon:Print("DMY trace not available.") end
                return
            end
            if sub2 == "fields" then
                if addon.DebugDMYFields then addon.DebugDMYFields()
                else addon:Print("DMY debug not available.") end
                return
            end
            if sub2 == "drilldown" then
                if addon.DebugDMYDrilldown then addon.DebugDMYDrilldown()
                else addon:Print("DMY debug not available.") end
                return
            end
            if sub2 == "drilldata" then
                if addon.DebugDMYDrilldata then addon.DebugDMYDrilldata()
                else addon:Print("DMY debug not available.") end
                return
            end
            if sub2 == "multicol" then
                if addon.DebugDMYMulticol then addon.DebugDMYMulticol()
                else addon:Print("DMY debug not available.") end
                return
            end
            if sub2 == "abbrev" then
                if addon.DebugDMYAbbrev then addon.DebugDMYAbbrev()
                else addon:Print("DMY debug not available.") end
                return
            end
            if sub2 == "colprobe" then
                if addon.DebugDMYColprobe then addon.DebugDMYColprobe()
                else addon:Print("DMY debug not available.") end
                return
            end
            addon:Print("Usage: /scoot debug dmY cvar")
            addon:Print("       /scoot debug dmY api")
            addon:Print("       /scoot debug dmY trace")
            addon:Print("       /scoot debug dmY fields")
            addon:Print("       /scoot debug dmY drilldown")
            addon:Print("       /scoot debug dmY drilldata")
            addon:Print("       /scoot debug dmY multicol")
            addon:Print("       /scoot debug dmY abbrev")
            addon:Print("       /scoot debug dmY colprobe")
            return
        end

        -- /scoot debug nametext - the Unit Frames Z name box, built as it would ship
        if sub1 == "nametext" then
            if not addon.DebugNameTextToggle then
                addon:Print("Name text debug not loaded.")
                return
            end
            if sub2 == "" then
                addon.DebugNameTextToggle()
                return
            end
            if sub2 == "size" then
                addon.DebugNameTextSetSize(args[4], args[5])
                return
            end
            if sub2 == "lines" then
                addon.DebugNameTextSetLines(args[4])
                return
            end
            if sub2 == "range" then
                addon.DebugNameTextSetRange(args[4], args[5])
                return
            end
            if sub2 == "fallback" then
                addon.DebugNameTextSetFallback(args[4])
                return
            end
            if sub2 == "mode" then
                addon.DebugNameTextSetMode(args[4])
                return
            end
            if sub2 == "font" then
                -- args[4] raw: font keys are case-sensitive (e.g. ROBOTO_REG)
                addon.DebugNameTextSetFont(args[4])
                return
            end
            if sub2 == "case" then
                -- args[5] raw: it is a font key, same reason as 'font' above
                addon.DebugNameTextSetCase(args[4], args[5])
                return
            end
            if sub2 == "caseprobe" then
                addon.DebugNameTextCaseProbe()
                return
            end
            if sub2 == "sample" then
                addon.DebugNameTextSample(args[4])
                return
            end
            if sub2 == "gradient" then
                addon.DebugNameTextSetGradient(args[4])
                return
            end
            if sub2 == "chrome" then
                addon.DebugNameTextToggleChrome()
                return
            end
            if sub2 == "margin" then
                addon.DebugNameTextSetMargin(args[4])
                return
            end
            if sub2 == "slices" then
                addon.DebugNameTextSetSlices(args[4])
                return
            end
            if sub2 == "class" then
                -- args[4] raw: class tokens are uppercase (DEATHKNIGHT, DEMONHUNTER)
                addon.DebugNameTextSetClass(args[4])
                return
            end
            if sub2 == "treatment" then
                addon.DebugNameTextSetTreatment(args[4])
                return
            end
            if sub2 == "identity" then
                addon.DebugNameTextSetIdentity(args[4])
                return
            end
            if sub2 == "scan" then
                addon.DebugNameTextScan()
                return
            end
            if sub2 == "lengthprobe" then
                addon.DebugNameTextLengthProbe()
                return
            end
            if sub2 == "fitprobe" then
                addon.DebugNameTextFitProbe(args[4])
                return
            end
            if sub2 == "autofit" then
                addon.DebugNameTextAutoFit()
                return
            end
            if sub2 == "report" then
                addon.DebugNameTextReport()
                return
            end
            addon:Print("Usage: /scoot debug nametext            (show/hide)")
            addon:Print("       /scoot debug nametext size <w> <h>")
            addon:Print("       /scoot debug nametext lines <n>")
            addon:Print("       /scoot debug nametext range <min> <max>")
            addon:Print("       /scoot debug nametext fallback <n>   (size when unmeasurable)")
            addon:Print("       /scoot debug nametext mode <font|scale|blizzard>")
            addon:Print("       /scoot debug nametext font <FACE>")
            addon:Print("       /scoot debug nametext case <normal|upper|smallcaps> [FACE]")
            addon:Print("       /scoot debug nametext caseprobe         (can string.upper touch a secret?)")
            addon:Print("       /scoot debug nametext sample <n>")
            addon:Print("       /scoot debug nametext gradient <auto|off|white|line|block|slice>")
            addon:Print("       /scoot debug nametext chrome            (backdrop on/off, to drag the box)")
            addon:Print("       /scoot debug nametext margin <auto|off|px>  (blind-spot safety margin)")
            addon:Print("       /scoot debug nametext slices <n>")
            addon:Print("       /scoot debug nametext class <TOKEN|auto>")
            addon:Print("       /scoot debug nametext treatment <cast|raw>")
            addon:Print("       /scoot debug nametext identity <player|class>")
            addon:Print("       /scoot debug nametext scan")
            addon:Print("       /scoot debug nametext lengthprobe")
            addon:Print("       /scoot debug nametext fitprobe [steps]  (does D(size) settle?)")
            addon:Print("       /scoot debug nametext autofit           (render, then show the size derivation)")
            addon:Print("       /scoot debug nametext report")
            return
        end

        local target = args[2]
        if not target or target == "" then
            addon:Print("Usage: /scoot debug <player|target|focus|pet|ab1..ab8|essential|utility|micro|stance|buffs|debuffs|offscreen|powerbarpos|dim|trackedbars|classauras|<FrameName>>")
            return
        end
        if addon.DebugDump then
            addon.DebugDump(target)
        else
            addon:Print("Debug module not loaded.")
        end
        return
    end

    -- /scoot attr
    if cmd == "attr" then
        if addon.DumpTableAttributes then
            addon:DumpTableAttributes()
        else
            addon:Print("Attribute dumper not available.")
        end
        return
    end

    -- /scoot taint <on|off|log|clear|status>
    if cmd == "taint" then
        if addon.TaintDebug and addon.TaintDebug.HandleSlashCommand then
            addon.TaintDebug.HandleSlashCommand(args)
        else
            addon:Print("Taint debug module not loaded.")
        end
        return
    end

    -- /scoot dj debug — Dungeon Journal diagnostics
    if cmd == "dj" then
        local sub = string.lower(args[2] or "")
        local DJ = addon.DungeonJournal
        if sub == "debug" then
            if not DJ then addon:Print("Dungeon Journal module not loaded.") return end
            addon:Print(string.format("DJ enabled: %s", tostring(DJ.IsEnabled and DJ.IsEnabled())))
            local ej = _G.EncounterJournal
            local instanceID = ej and rawget(ej, "instanceID") or nil
            addon:Print(string.format("EJ.instanceID: %s", tostring(instanceID)))
            if type(instanceID) == "number" and EJ_GetInstanceInfo then
                local ok, name, _, _, _, _, _, dungeonAreaMapID = pcall(EJ_GetInstanceInfo, instanceID)
                if ok then
                    addon:Print(string.format("  name=%s  dungeonAreaMapID=%s",
                        tostring(name), tostring(dungeonAreaMapID)))
                end
                addon:Print(string.format("  IsCurrentSeasonInstance: %s",
                    tostring(DJ.IsCurrentSeasonInstance and DJ.IsCurrentSeasonInstance(instanceID))))
            end
            local s = DJ._SeasonDebug and DJ._SeasonDebug() or {}
            addon:Print(string.format("Snapshot: have=%s  requested=%s",
                tostring(s.haveSnapshot), tostring(s.requestedOnce)))
            local nameCount = 0
            for n in pairs(s.seasonNames or {}) do
                nameCount = nameCount + 1
                addon:Print(string.format("  season name: %s", n))
            end
            addon:Print(string.format("  total season names: %d", nameCount))
            addon:Print(string.format("Marks on this character: %d",
                (DJ.CountMarks and DJ.CountMarks()) or 0))
            return
        end
        addon:Print("Usage: /scoot dj debug")
        return
    end

    -- /scoot widget <reset|state>
    if cmd == "widget" then
        local sub = string.lower(args[2] or "")
        if sub == "reset" then
            if addon.Widget and addon.Widget.ResetPosition then
                addon.Widget:ResetPosition()
                addon:Print("Widget position reset.")
            else
                addon:Print("Widget module not loaded.")
            end
            return
        end
        if sub == "state" then
            if addon.DebugWidgetState then
                addon.DebugWidgetState()
            else
                addon:Print("Widget debug not loaded.")
            end
            return
        end
        addon:Print("Usage: /scoot widget reset")
        addon:Print("       /scoot widget state")
        return
    end

    -- /scoot copy "Source Name" "New Name"
    if cmd == "copy" then
        local src = args[2]
        local dest = args[3]
        if not src or not dest then addon:Print("Usage: /scoot copy \"Source Name\" \"New Name\"") return end
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
        return
    end

    -- Fallback: open settings
    if addon.UI and addon.UI.SettingsPanel and addon.UI.SettingsPanel.Toggle then
        addon.UI.SettingsPanel:Toggle()
    end
end

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
