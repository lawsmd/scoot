-- restyle.lua - What Scoot does to the screen when the active profile changes
--
-- The profile engine (core.lua, layouts.lua, spec.lua) is host-neutral and
-- loads under both addons. This file is Scoot's side of the seam: the one apply
-- step that re-links components, restyles, reconciles the profile-driven
-- toggles and the aura systems, and the import hook the Personal Resource
-- Display needs. Camelot has its own file for the same seam.
local _, addon = ...

local Profiles = addon.Profiles

Profiles.RegisterApplyStep("scoot", function(reason, ctx)
    if ctx.initial then
        -- Bar enable settings do not exist yet at Initialize (ADDON_LOADED);
        -- Blizzard registers them only after VARIABLES_LOADED and
        -- PLAYER_ENTERING_WORLD. Arm the SETTINGS_LOADED hook unconditionally;
        -- it is what applies the profile on login. The action bar reconcile
        -- inside the toggles pass is a harmless no-op until then.
        Profiles._ensureBarSettingsArrivalHook()
        Profiles._reconcileProfileToggles("Initialize")
        return
    end

    if ctx.switch then
        -- Switching to an empty (zero-touch) profile without a reload: clear
        -- frame-level enforcement flags so old-profile hooks stop forcing
        -- hidden states.
        local profile = addon.db and addon.db.profile
        local unitFrames = profile and rawget(profile, "unitFrames") or nil
        local components = profile and rawget(profile, "components") or nil
        local hasUF = type(unitFrames) == "table" and next(unitFrames) ~= nil
        local hasComponents = type(components) == "table" and next(components) ~= nil
        if (not hasUF) and (not hasComponents) and addon.ClearFrameLevelState then
            addon:ClearFrameLevelState()
        end
    end

    addon:LinkComponentsToDB()
    addon:ApplyStyles()
    Profiles._reconcileProfileToggles(reason)

    if addon.ScootAuras and addon.ScootAuras.ReconcileForActiveProfile then
        addon.ScootAuras.ReconcileForActiveProfile(reason)
    end
    if addon.AuraTracking and addon.AuraTracking.OnConfigChanged then
        -- Group-frame aura slots are per-profile: a switch has to retire the
        -- old profile's spells and point slots at the new ones.
        addon.AuraTracking.OnConfigChanged()
    end
end, 10)

-- Personal Resource Display mirrors: push the imported PRD values into the
-- layout the first time this profile is active with Edit Mode ready.
Profiles.RegisterImportHook("prd", function(profileTable)
    if addon.PRD and addon.PRD.MarkProfilePendingNativePush then
        addon.PRD.MarkProfilePendingNativePush(profileTable)
    end
end)
