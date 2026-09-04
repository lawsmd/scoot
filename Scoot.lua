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
