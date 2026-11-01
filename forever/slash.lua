--------------------------------------------------------------------------------
-- forever/slash.lua
-- The slash word. A bare /camelot opens the settings panel, the one behavior
-- that is this addon's; every verb dispatches through the command registry in
-- core/commands.lua, which reads the brand and the word off the entry file.
--
-- Last of the shipped files on Camelot.toc, after every file that registers a
-- verb at file scope. The development tooling after it registers more verbs
-- once the word is bound, which is fine: the registry dispatches at call time.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.Commands.InstallSlash(function()
    if addon.UI and addon.UI.SettingsPanel and addon.UI.SettingsPanel.Toggle then
        addon.UI.SettingsPanel:Toggle()
    end
end)
