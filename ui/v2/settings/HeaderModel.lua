-- settings/HeaderModel.lua - Scoot's title and toolbar for the settings panel.
--
-- ui/v2/settingspanel/core.lua reads addon.UI.SettingsPanel.HeaderModel when
-- it builds the panel and at every page change: title is what the title bar
-- and the home page show, in whichever presentation the skin's titleBar
-- role picks (ascii, text or texture), and toolbar is the row of buttons
-- across the top edge. Camelot supplies its own in forever/menu.lua.
--
-- A toolbar entry is { key, label, action, pulseWhen, isVisible }. action.kind
-- is "page" (select the nav key in action.page), "editMode" (Blizzard's Edit
-- Mode through a secure click) or "call" (action.fn(panel)). pulseWhen and
-- isVisible are optional functions.
local addonName, addon = ...

-- Listed before ui/v2/settingspanel/core.lua on Scoot.toc, so the table is
-- created here when this file is first to it.
addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel

local ASCII_LOGO = [[
 ██████╗ █████╗  █████╗  █████╗ ████████╗
██╔════╝██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝
╚█████╗ ██║  ╚═╝██║  ██║██║  ██║   ██║
 ╚═══██╗██║  ██╗██║  ██║██║  ██║   ██║
██████╔╝╚█████╔╝╚█████╔╝╚█████╔╝   ██║
╚═════╝  ╚════╝  ╚════╝  ╚════╝    ╚═╝ ]]

-- The mascot beside "Welcome to" on the home page (54 columns wide).
local ASCII_MASCOT = [[
                             ***
         .==.              **====*
         ..==            *==========
          .==          **======....-==
          .==-        ***=====...   .==
          .==:       **=======....   =*
          .==:     .*******==-....
          .==:  ***..========-***..
           ==. .--..@@@@%@@@@*@==..-==
           ==:    .     -    :@@@=%=..=
            =:    *%   %%%   #@@===+
            =:     %%*@@@@@@%@@@==%
            =:      @@=====@@@@@...
           %+=##= *@@@@@@@@@@@@.-==-..
          %%%%===.+@@@@@@@@@@@@..====..
          %%%%=%===.@@@@@@@@@*....====..
           %%+.=..=..=@@@@@@.==....*===..
             :...... ===@..=====...**===.
             -:-..  ......===..   .#****-
             -=.    ...............=%%%%*
             -=.    ***==========..:=====
              =.   **=============..=
              =.. ***==============.==
              =-. *+================-:=*
              ==..==....=========..==...*
              .=.=====...........======.-=*]]

UIPanel.HeaderModel = {
    title = { text = "Scoot", ascii = ASCII_LOGO, mascot = ASCII_MASCOT },
    toolbar = {
        {
            key = "features", label = "Features",
            action = { kind = "page", page = "startHere" },
            -- The Features button pulses while every module is off
            pulseWhen = function()
                return addon.AreAllModulesDisabled and addon:AreAllModulesDisabled() or false
            end,
        },
        { key = "search", label = "Search", action = { kind = "page", page = "search" } },
        { key = "editMode", label = "Edit Mode", action = { kind = "editMode" } },
        {
            key = "cdm", label = "Cooldown Manager",
            action = {
                kind = "call",
                fn = function(panel)
                    if addon.OpenCooldownManagerSettings then
                        addon:OpenCooldownManagerSettings()
                    end
                    if panel.frame and panel.frame:IsShown() then
                        panel.frame:Hide()
                    end
                end,
            },
        },
    },
}
