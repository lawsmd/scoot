-- cvars.lua - Per-profile CVar enforcement (Zero-Touch: an unset toggle never writes)
local _, addon = ...
local Events = addon.Events

-- Aliases for internals promoted by core.lua
local Debug = addon.Profiles._Debug

-- The one write body every applier shares: C_CVar first, legacy fallback.
local function setCVarValue(name, value)
    if C_CVar and C_CVar.SetCVar then
        pcall(C_CVar.SetCVar, name, value)
    elseif SetCVar then
        pcall(SetCVar, name, value)
    end
end

-- Setting a CVar does not reliably hide already-visible frames until the user
-- toggles Blizzard's checkbox UI, so a disable proactively hides them. Avoids
-- touching potentially protected UI during combat; retries once shortly after.
local function hideFramesAfterDisable(frameNames)
    local function hideAll()
        for _, frameName in ipairs(frameNames) do
            local frame = _G and _G[frameName]
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
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, function()
                if not (InCombatLockdown and InCombatLockdown()) then
                    hideAll()
                end
            end)
        end
    else
        hideAll()
    end
end

-- One applier per profile-driven CVar. Fields:
--   tag        RunOutOfCombat owner-key suffix; the key is "Profiles:" .. tag
--   cvar       the CVar written, also named in the Debug line
--   module     optional addon:IsModuleEnabled gate
--   desired    reads the profile subtable; nil means Zero-Touch skip
--   invert     the toggle means the opposite of the CVar
--   preempt    optional full override; returns true when it handled the apply
--   postApply  runs after the write is scheduled
local function applyFromProfile(d, reason)
    if d.module and not addon:IsModuleEnabled(d.module) then return end
    if d.preempt and d.preempt(reason) then return end
    local profile = addon and addon.db and addon.db.profile
    local desired = d.desired(profile)
    if desired == nil then
        return  -- Zero-Touch: never override until the user configures the toggle
    end
    local value
    if d.invert then
        value = (desired and "0") or "1"
    else
        value = (desired and "1") or "0"
    end

    Events.RunOutOfCombat(function()
        setCVarValue(d.cvar, value)
    end, "Profiles:" .. d.tag)

    if d.postApply then d.postApply(desired) end

    Debug("Applied " .. d.cvar .. " from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

-- Apply the profile's CDM override (if explicitly set) to the Blizzard CVar.
-- This is character-scoped in Blizzard, so it is enforced per-profile by setting it
-- when the active Scoot profile changes.
local cooldownViewerEnabled = {
    tag = "cdmCVar",
    cvar = "cooldownViewerEnabled",
    module = "cooldownManager",
    desired = function(profile)
        local q = profile and profile.cdmQoL
        return q and q.enableCDM
    end,
    -- Intentionally does NOT force-show when enabling; Edit Mode + viewer visibility
    -- settings (and Blizzard state) should remain the source of truth for whether a
    -- particular viewer is currently visible.
    postApply = function(desired)
        if desired == false then
            hideFramesAfterDisable({
                "EssentialCooldownViewer",
                "UtilityCooldownViewer",
                "BuffIconCooldownViewer",
                "BuffBarCooldownViewer",
            })
        end
    end,
}

local nameplateShowSelf = {
    tag = "prdCVar",
    cvar = "nameplateShowSelf",
    module = "prd",
    desired = function(profile)
        local s = profile and profile.prdSettings
        return s and s.enablePRD
    end,
    -- If disabling, trigger a re-apply so borders/overlays get cleared
    postApply = function(desired)
        if desired == false then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end)
            end
        end
    end,
}

local damageMeterEnabled = {
    tag = "dmCVar",
    cvar = "damageMeterEnabled",
    module = "damageMeter",
    -- V2 active → always disable Blizzard's meter regardless of V1 settings.
    preempt = function(reason)
        if not addon:IsModuleEnabled("damageMeter", "damageMeterV2") then return false end
        -- Same key as the V1 path below: both write damageMeterEnabled, so a
        -- V1/V2 flip mid-combat must resolve to the latest write only.
        Events.RunOutOfCombat(function()
            setCVarValue("damageMeterEnabled", "0")
        end, "Profiles:dmCVar")
        -- Hide Blizzard meter frame. In combat the hide is skipped, with no retry;
        -- the deferred CVar write above still lands on regen.
        if not (InCombatLockdown and InCombatLockdown()) then
            local frame = _G and _G["DamageMeter"]
            if frame then
                if frame.SetShown then pcall(frame.SetShown, frame, false)
                elseif frame.Hide then pcall(frame.Hide, frame)
                end
            end
        end
        Debug("Applied damageMeterEnabled=0 for V2", reason and ("reason=" .. tostring(reason)) or "")
        return true
    end,
    desired = function(profile)
        local s = profile and profile.damageMeterSettings
        return s and s.enableDamageMeter
    end,
    -- Hide damage meter if disabling (same pattern as CDM)
    postApply = function(desired)
        if desired == false then
            hideFramesAfterDisable({ "DamageMeter" })
        end
    end,
}

-- Raid frames: Blizzard renders raid-frame debuffs as private auras (forbidden,
-- secure environment) and enlarges boss/role-specific ones when its
-- "Display Larger Role-Specific Auras" option is on. Those borders cannot be
-- restyled, but the CVar that drives them can be flipped. Setting the CVar fires
-- CompactUnitFrameProfiles' CVar callback, which reapplies to all raid +
-- raid-style party frames automatically (no manual rebuild).
local raidLargerRoleDebuffs = {
    tag = "raidRoleDebuffsCVar",
    cvar = "raidFramesDisplayLargerRoleSpecificDebuffs",
    desired = function(profile)
        local gf = profile and profile.groupFrames
        local s = gf and gf.raid
        return s and s.enlargeRoleDebuffs
    end,
}

-- Group frames: patch 12.1 added the raidFramesDisplayBuffs CVar, an engine-level switch
-- that removes every buff icon from raid and raid-style party frames (the frames read it
-- through CompactUnitFrameProfiles' CVar callback, which reapplies frame setup on its own).
-- Blizzard wired the CVar but exposed no options UI for it; Scoot's Aura Tracking page does.
local groupBuffIconsHidden = {
    tag = "groupBuffIconsCVar",
    cvar = "raidFramesDisplayBuffs",
    -- Inverted polarity: the toggle means "hide", the CVar means "display".
    invert = true,
    desired = function(profile)
        local gf = profile and profile.groupFrames
        local at = gf and gf.auraTracking

        -- One-shot conversion from the retired replacementStyle overlay setting. Runs here as
        -- well as in ensureAuraTrackingDB (ui/v2/groupframes/Helpers.lua) because this function
        -- fires at login before any settings UI code touches the profile. Both copies are
        -- idempotent; keep them in sync. Runs before the nil check on purpose.
        if at and at.replacementStyle ~= nil then
            if at.replacementStyle ~= "none" and at.hideBlizzardBuffIcons == nil then
                at.hideBlizzardBuffIcons = true
            end
            at.replacementStyle = nil
        end

        return at and at.hideBlizzardBuffIcons
    end,
}

local function makeApplier(d)
    return function(reason)
        applyFromProfile(d, reason)
    end
end

-- Expose for the Raid Frames renderer toggle so it reuses the one combat-guarded implementation.
addon.ApplyRaidLargerRoleDebuffs = makeApplier(raidLargerRoleDebuffs)

-- Expose for the Aura Tracking renderer toggle so it reuses the one combat-guarded implementation.
addon.ApplyGroupBuffIconsHidden = makeApplier(groupBuffIconsHidden)

-- Per-profile enforcement that ApplyStyles does not cover: the CVar-backed
-- toggles, the action bar enable state, and chat. Every profile-apply site
-- runs it.
local function reconcileProfileToggles(reason)
    applyFromProfile(cooldownViewerEnabled, reason)
    applyFromProfile(nameplateShowSelf, reason)
    applyFromProfile(damageMeterEnabled, reason)
    addon.ReconcileActionBarsEnabled(reason)
    applyFromProfile(raidLargerRoleDebuffs, reason)
    applyFromProfile(groupBuffIconsHidden, reason)
    if addon and addon.Chat and addon.Chat.ApplyFromProfile then
        addon.Chat:ApplyFromProfile("Profiles:" .. reason)
    end
end

-- Expose for applyActiveProfile and Profiles:Initialize (core.lua).
addon.Profiles._reconcileProfileToggles = reconcileProfileToggles
