-- cvars.lua - Per-profile CVar enforcement (Zero-Touch: an unset toggle never writes)
local _, addon = ...
local Events = addon.Events

-- Aliases for internals promoted by core.lua
local Debug = addon.Profiles._Debug

-- Apply the profile's CDM override (if explicitly set) to the Blizzard CVar.
-- This is character-scoped in Blizzard, so it is enforced per-profile by setting it
-- when the active Scoot profile changes.
local function ApplyCooldownViewerEnabledForActiveProfile(reason)
    if not addon:IsModuleEnabled("cooldownManager") then return end
    local profile = addon and addon.db and addon.db.profile
    local q = profile and profile.cdmQoL
    local desired = q and q.enableCDM
    if desired == nil then
        return
    end
    local value = (desired and "1") or "0"

    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "cooldownViewerEnabled", value)
        elseif SetCVar then
            pcall(SetCVar, "cooldownViewerEnabled", value)
        end
    end

    Events.RunOutOfCombat(applyCVar, "Profiles:cdmCVar")

    -- Important: setting the CVar does not reliably hide already-visible CDM frames
    -- until the user toggles Blizzard's checkbox UI. If the profile explicitly disables
    -- CDM, the viewer frames must be proactively hidden so the UI matches the setting
    -- immediately (including right after /reload).
    --
    -- Intentionally does NOT force-show when enabling; Edit Mode + viewer visibility
    -- settings (and Blizzard state) should remain the source of truth for whether a
    -- particular viewer is currently visible.
    if desired == false then
        local function hideViewers()
            local viewers = {
                "EssentialCooldownViewer",
                "UtilityCooldownViewer",
                "BuffIconCooldownViewer",
                "BuffBarCooldownViewer",
            }
            for _, viewerName in ipairs(viewers) do
                local frame = _G and _G[viewerName]
                if frame then
                    if frame.SetShown then
                        pcall(frame.SetShown, frame, false)
                    elseif frame.Hide then
                        pcall(frame.Hide, frame)
                    end
                end
            end
        end

        if InCombatLockdown and InCombatLockdown() then
            -- Avoid touching potentially protected UI during combat; retry after combat ends.
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, function()
                    if not (InCombatLockdown and InCombatLockdown()) then
                        hideViewers()
                    end
                end)
            end
        else
            hideViewers()
        end
    end

    Debug("Applied cooldownViewerEnabled from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

local function ApplyPRDEnabledForActiveProfile(reason)
    if not addon:IsModuleEnabled("prd") then return end
    local profile = addon and addon.db and addon.db.profile
    local s = profile and profile.prdSettings
    local desired = s and s.enablePRD
    if desired == nil then
        return  -- Not explicitly set; don't override CVar
    end
    local value = (desired and "1") or "0"

    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "nameplateShowSelf", value)
        elseif SetCVar then
            pcall(SetCVar, "nameplateShowSelf", value)
        end
    end

    Events.RunOutOfCombat(applyCVar, "Profiles:prdCVar")

    -- If disabling, trigger a re-apply so borders/overlays get cleared
    if desired == false then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if addon and addon.ApplyStyles then
                    addon:ApplyStyles()
                end
            end)
        end
    end

    Debug("Applied nameplateShowSelf from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

local function ApplyDamageMeterEnabledForActiveProfile(reason)
    if not addon:IsModuleEnabled("damageMeter") then return end

    -- V2 active → always disable Blizzard's meter regardless of V1 settings
    if addon:IsModuleEnabled("damageMeter", "damageMeterV2") then
        local function applyV2CVar()
            if C_CVar and C_CVar.SetCVar then
                pcall(C_CVar.SetCVar, "damageMeterEnabled", "0")
            elseif SetCVar then
                pcall(SetCVar, "damageMeterEnabled", "0")
            end
        end
        -- Same key as the V1 path below: both write damageMeterEnabled, so a
        -- V1/V2 flip mid-combat must resolve to the latest write only.
        Events.RunOutOfCombat(applyV2CVar, "Profiles:dmCVar")
        -- Hide Blizzard meter frame
        if not (InCombatLockdown and InCombatLockdown()) then
            local frame = _G and _G["DamageMeter"]
            if frame then
                if frame.SetShown then pcall(frame.SetShown, frame, false)
                elseif frame.Hide then pcall(frame.Hide, frame)
                end
            end
        end
        Debug("Applied damageMeterEnabled=0 for V2", reason and ("reason=" .. tostring(reason)) or "")
        return
    end

    local profile = addon and addon.db and addon.db.profile
    local s = profile and profile.damageMeterSettings
    local desired = s and s.enableDamageMeter
    if desired == nil then
        return  -- Not explicitly set; don't override CVar
    end
    local value = (desired and "1") or "0"

    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "damageMeterEnabled", value)
        elseif SetCVar then
            pcall(SetCVar, "damageMeterEnabled", value)
        end
    end

    Events.RunOutOfCombat(applyCVar, "Profiles:dmCVar")

    -- Hide damage meter if disabling (same pattern as CDM)
    if desired == false then
        local function hideDamageMeter()
            local frame = _G and _G["DamageMeter"]
            if frame then
                if frame.SetShown then
                    pcall(frame.SetShown, frame, false)
                elseif frame.Hide then
                    pcall(frame.Hide, frame)
                end
            end
        end

        if InCombatLockdown and InCombatLockdown() then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, function()
                    if not (InCombatLockdown and InCombatLockdown()) then
                        hideDamageMeter()
                    end
                end)
            end
        else
            hideDamageMeter()
        end
    end

    Debug("Applied damageMeterEnabled from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

-- Raid frames: Blizzard renders raid-frame debuffs as private auras (forbidden,
-- secure environment) and enlarges boss/role-specific ones when its
-- "Display Larger Role-Specific Auras" option is on. Those borders cannot be
-- restyled, but the CVar that drives them can be flipped. Setting the CVar fires
-- CompactUnitFrameProfiles' CVar callback, which reapplies to all raid +
-- raid-style party frames automatically (no manual rebuild).
local function ApplyRaidLargerRoleDebuffsForActiveProfile(reason)
    local profile = addon and addon.db and addon.db.profile
    local gf = profile and profile.groupFrames
    local s = gf and gf.raid
    local desired = s and s.enlargeRoleDebuffs
    if desired == nil then
        return  -- Zero-Touch: never override until the user configures the toggle
    end
    local value = (desired and "1") or "0"

    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "raidFramesDisplayLargerRoleSpecificDebuffs", value)
        elseif SetCVar then
            pcall(SetCVar, "raidFramesDisplayLargerRoleSpecificDebuffs", value)
        end
    end

    Events.RunOutOfCombat(applyCVar, "Profiles:raidRoleDebuffsCVar")

    Debug("Applied raidFramesDisplayLargerRoleSpecificDebuffs from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

-- Expose for the Raid Frames renderer toggle so it reuses the one combat-guarded implementation.
addon.ApplyRaidLargerRoleDebuffs = ApplyRaidLargerRoleDebuffsForActiveProfile

-- Group frames: patch 12.1 added the raidFramesDisplayBuffs CVar, an engine-level switch
-- that removes every buff icon from raid and raid-style party frames (the frames read it
-- through CompactUnitFrameProfiles' CVar callback, which reapplies frame setup on its own).
-- Blizzard wired the CVar but exposed no options UI for it; Scoot's Aura Tracking page does.
local function ApplyGroupBuffIconsHiddenForActiveProfile(reason)
    local profile = addon and addon.db and addon.db.profile
    local gf = profile and profile.groupFrames
    local at = gf and gf.auraTracking

    -- One-shot conversion from the retired replacementStyle overlay setting. Runs here as
    -- well as in ensureAuraTrackingDB (ui/v2/groupframes/Helpers.lua) because this function
    -- fires at login before any settings UI code touches the profile. Both copies are
    -- idempotent; keep them in sync.
    if at and at.replacementStyle ~= nil then
        if at.replacementStyle ~= "none" and at.hideBlizzardBuffIcons == nil then
            at.hideBlizzardBuffIcons = true
        end
        at.replacementStyle = nil
    end

    local desired = at and at.hideBlizzardBuffIcons
    if desired == nil then
        return  -- Zero-Touch: never override until the user configures the toggle
    end
    -- Inverted polarity: the toggle means "hide", the CVar means "display".
    local value = (desired and "0") or "1"

    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "raidFramesDisplayBuffs", value)
        elseif SetCVar then
            pcall(SetCVar, "raidFramesDisplayBuffs", value)
        end
    end

    Events.RunOutOfCombat(applyCVar, "Profiles:groupBuffIconsCVar")

    Debug("Applied raidFramesDisplayBuffs from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

-- Expose for the Aura Tracking renderer toggle so it reuses the one combat-guarded implementation.
addon.ApplyGroupBuffIconsHidden = ApplyGroupBuffIconsHiddenForActiveProfile

-- Per-profile enforcement that ApplyStyles does not cover: the CVar-backed
-- toggles, the action bar enable state, and chat. Every profile-apply site
-- runs it.
local function reconcileProfileToggles(reason)
    ApplyCooldownViewerEnabledForActiveProfile(reason)
    ApplyPRDEnabledForActiveProfile(reason)
    ApplyDamageMeterEnabledForActiveProfile(reason)
    addon.ReconcileActionBarsEnabled(reason)
    ApplyRaidLargerRoleDebuffsForActiveProfile(reason)
    ApplyGroupBuffIconsHiddenForActiveProfile(reason)
    if addon and addon.Chat and addon.Chat.ApplyFromProfile then
        addon.Chat:ApplyFromProfile("Profiles:" .. reason)
    end
end

-- Expose for applyActiveProfile and Profiles:Initialize (core.lua).
addon.Profiles._reconcileProfileToggles = reconcileProfileToggles
