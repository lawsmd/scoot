--------------------------------------------------------------------------------
-- forever/profiles.lua
-- Camelot's side of the profile engine.
--
-- The engine (core/profiles/core.lua, layouts.lua, spec.lua, and the layout
-- persistence in core/editmode/persist.lua) is listed on Camelot.toc and
-- builds its own instance here. It keys every AceDB profile to an Edit Mode
-- layout name and drives create, copy, rename, delete, switch, spec
-- assignment and the reload handshake. This file supplies what the engine
-- asks of its host: when to initialize, which events reach it, and what
-- happens on screen after the active profile changes.
--
-- The profile containers (modules, settings, documents, layout) are not
-- re-created here. Every switch the engine makes goes through AceDB's
-- SetProfile, and the watcher in forever/db.lua rebuilds them on that
-- callback before anything reads them.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Profiles = addon.Profiles

-- What Camelot does to the screen after a profile's contents change. The
-- initial pass runs at ADDON_LOADED with no world state; nothing to do there
-- yet. Every other pass re-reads the profile into the frames Camelot owns,
-- through whatever refresh the unit frames expose once they have one.
Profiles.RegisterApplyStep("camelot", function(reason, ctx)
    if ctx.initial then return end
    local frames = addon.UnitFrames
    if frames and type(frames.RefreshAll) == "function" then
        frames.RefreshAll(reason)
    end
end, 10)

-- addon.db exists once forever/db.lua has run its own ADDON_LOADED callback;
-- callbacks run in registration order and db.lua is listed first.
addon.Events.OnAddonLoaded(addonName, function()
    Profiles:Initialize()
    addon.EditMode.InstallLayoutHooks()
end)

-- The three world events the engine asks its host to forward. On Forever the
-- first OnEnteringWorld is what loads the layout list: the probe showed
-- LibEditModeOverride reporting AreLayoutsLoaded false until LoadLayouts runs.
addon.Events.On("Profiles", "PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
    Profiles:OnEnteringWorld(isInitialLogin, isReloadingUi)
end)

addon.Events.On("Profiles", "EDIT_MODE_LAYOUTS_UPDATED", function()
    Profiles:OnLayoutsUpdated()
end)

addon.Events.On("Profiles", "PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
    if unit and unit ~= "player" then return end
    Profiles:OnSpecChanged()
end)
