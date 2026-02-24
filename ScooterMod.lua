local addonName, addon = ...

LibStub("AceAddon-3.0"):NewAddon(addon, "ScooterMod", "AceEvent-3.0")
_G.ScooterModAddon = addon
_G.ScooterMod = addon

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
-- Returns true if we successfully opened a target frame, false otherwise.
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

SLASH_SCOOTERMOD1 = "/scoot"
function SlashCmdList.SCOOTERMOD(msg, editBox)
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
            addon:Print("  /scoot debug <player|target|focus|pet|ab1..ab8|essential|utility|micro|stance|buffs|debuffs|offscreen|powerbarpos|dim|trackedbars|classauras|<FrameName>>")
            addon:Print("  /scoot debug profiles export [\"Profile Name\"]")
            addon:Print("  /scoot debug consoleport export")
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
            addon:Print("Usage: /scoot debug profiles export [\"Profile Name\"]")
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
                addon:Print("Usage: /scoot debug trackedbars <trace|log|clear|dump>")
                addon:Print("  trace on  - Start tracing bar lifecycle events")
                addon:Print("  trace off - Stop tracing")
                addon:Print("  log       - Show trace buffer in copyable window")
                addon:Print("  clear     - Clear the trace buffer")
                addon:Print("  dump      - Snapshot current state of all bar items")
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
SLASH_SCOOTERCDM1 = "/cdm"
function SlashCmdList.SCOOTERCDM(msg, editBox)
    local profile = addon and addon.db and addon.db.profile
    local enabled = profile and profile.cdmQoL and profile.cdmQoL.enableSlashCDM
    if not enabled then
        if addon and addon.Print then
            addon:Print("Enable /cdm in ScooterMod → Cooldown Manager → Quality of Life.")
        end
        return
    end
    addon:OpenCooldownManagerSettings()
end


-- NOTE: PLAYER_TARGET_CHANGED is handled in core/init.lua via PLAYER_TARGET_CHANGED()
-- which calls RefreshOpacityState() - this is combat-safe and properly updates opacity
-- for all components (Action Bars, CDM, Auras, etc.) without blocking during combat.
-- Do NOT register a duplicate handler here as it would overwrite the init.lua handler.
