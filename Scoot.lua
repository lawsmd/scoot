-- Scoot.lua - Addon entry point and AceAddon bootstrap
local addonName, addon = ...

LibStub("AceAddon-3.0"):NewAddon(addon, "Scoot", "AceEvent-3.0")
_G.ScootAddon = addon
_G.Scoot = addon

local function PrintScootMessage(text)
    if not text or text == "" then return end
    -- Built per print, not hoisted to a file-scope constant: the prefix is a
    -- brand mark and follows the accent, which the user can change mid session.
    -- The only guarded accent read in the addon. This is the channel that
    -- reports a broken load, so it has to survive ui/v2/Theme.lua failing to
    -- load at all; everywhere else a missing resolver is already fatal.
    local hex = addon.GetAccentHex and addon.GetAccentHex() or "00ff41"
    local prefix = "|cff" .. hex .. "[SCOOT]|r"
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

-- addon:OpenCooldownManagerSettings lives in core/cooldownsettings.lua, which
-- both TOCs list.

-- /scoot. The registry owns the word, the parse and the dispatch; opening the
-- settings panel on a bare /scoot is the part that is this addon's alone.
addon.Commands.InstallSlash(function()
    if addon.UI and addon.UI.SettingsPanel and addon.UI.SettingsPanel.Toggle then
        addon.UI.SettingsPanel:Toggle()
    end
end)

-- debugmenu stays with the bootstrap: it toggles a profile flag the settings panel reads.
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

-- /dmshow and /dmreset are installed by the damage meter's own initializer
-- (core/components/damagemetersY/styling.lua, DMY._InstallSlashWords).


-- PLAYER_TARGET_CHANGED is handled in core/init.lua — do not duplicate here.
