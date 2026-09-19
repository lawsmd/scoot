-- core/cooldownsettings.lua - opens Blizzard's Cooldown Manager settings.
--
-- One file for both addons: the settings panel's toolbar and the Game Menu
-- call it, and Scoot's /cdm and spellbook overlay with them.
local addonName, addon = ...

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
