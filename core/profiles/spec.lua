local _, addon = ...
local Profiles = addon.Profiles

-- Aliases for internals promoted by core.lua
local Debug = addon.Profiles._Debug
local getCurrentSpecID = addon.Profiles._getCurrentSpecID

function Profiles:GetSpecConfig()
    if not self.db or not self.db.char then
        return nil
    end
    local char = self.db.char
    char.specProfiles = char.specProfiles or {}
    local cfg = char.specProfiles
    if cfg.assignments == nil then
        cfg.assignments = {}
    end
    return cfg
end

function Profiles:IsSpecProfilesEnabled()
    local cfg = self:GetSpecConfig()
    return cfg and cfg.enabled or false
end

function Profiles:SetSpecProfilesEnabled(enabled)
    local cfg = self:GetSpecConfig()
    if cfg then
        cfg.enabled = not not enabled
    end
end

function Profiles:SetSpecAssignment(specID, profileKey)
    if not specID then
        return
    end
    local cfg = self:GetSpecConfig()
    if not cfg then
        return
    end
    if type(profileKey) ~= "string" or profileKey == "" then
        cfg.assignments[specID] = nil
    else
        cfg.assignments[specID] = profileKey
    end
end

function Profiles:GetSpecAssignment(specID)
    local cfg = self:GetSpecConfig()
    if not cfg or not cfg.assignments then
        return nil
    end
    return cfg.assignments[specID]
end

function Profiles:PruneSpecAssignments()
    local cfg = self:GetSpecConfig()
    if not cfg or not cfg.assignments then
        return
    end
    for specID, profileKey in pairs(cfg.assignments) do
        if profileKey and not self._layoutLookup[profileKey] then
            cfg.assignments[specID] = nil
        end
    end
end

-- Auto-heal: remove AceDB profiles that no longer have a corresponding Edit Mode layout.
-- This can happen when layouts are deleted outside Scoot, or when SavedVariables are
-- moved between machines but Blizzard's Edit Mode layout list does not match.
function Profiles:CleanupOrphanedProfiles()
    if not self.db or not self.db.profiles or not self._layoutLookup then
        return
    end

    local protected = {
        ["Default"] = true, -- AceDB shared default (we use AceDB:New(..., true))
        ["Modern"] = true,  -- Blizzard preset layout name (may have a profile mirror)
        ["Classic"] = true, -- Blizzard preset layout name (may have a profile mirror)
    }

    local currentProfile = self.db.GetCurrentProfile and self.db:GetCurrentProfile() or nil
    local orphaned = {}

    for profileName in pairs(self.db.profiles) do
        if type(profileName) == "string"
            and not protected[profileName]
            and profileName ~= currentProfile
            and not self._layoutLookup[profileName]
        then
            orphaned[#orphaned + 1] = profileName
        end
    end

    if #orphaned == 0 then
        return
    end

    table.sort(orphaned, function(a, b) return tostring(a) < tostring(b) end)

    -- Clean up AceDB cross-character bindings (profileKeys) and Spec Profiles assignments.
    local sv = rawget(self.db, "sv")
    local cfg = self:GetSpecConfig()

    for _, name in ipairs(orphaned) do
        self.db.profiles[name] = nil

        if sv and sv.profileKeys then
            for key, value in pairs(sv.profileKeys) do
                if value == name then
                    sv.profileKeys[key] = nil
                end
            end
        end

        if cfg and cfg.assignments then
            for specID, profileKey in pairs(cfg.assignments) do
                if profileKey == name then
                    cfg.assignments[specID] = nil
                end
            end
        end

        Debug("CleanupOrphanedProfiles removed", name)
    end
end

-- Detect when the current profile's Edit Mode layout was deleted externally (via Blizzard's Edit Mode UI).
-- This is called from RefreshFromEditMode after _layoutLookup is rebuilt.
-- If the current profile no longer has a matching layout, prompt for reload.
function Profiles:CheckForExternalDeletion()
    if not self.db or not self._layoutLookup then
        return
    end

    -- Skip if we already prompted this session (avoid spamming on rapid events)
    if self._externalDeletionPrompted then
        return
    end

    local protected = {
        ["Default"] = true,
        ["Modern"] = true,
        ["Classic"] = true,
    }

    local currentProfile = self.db:GetCurrentProfile()
    if not currentProfile or protected[currentProfile] then
        return
    end

    -- If the current profile has no matching Edit Mode layout, it was deleted externally
    if not self._layoutLookup[currentProfile] then
        self._externalDeletionPrompted = true
        Debug("CheckForExternalDeletion: current profile has no matching layout", currentProfile)

        -- Defer the dialog slightly to allow any pending UI updates to complete
        C_Timer.After(0.1, function()
            if addon and addon.Dialogs and addon.Dialogs.Show then
                addon.Dialogs:Show("SCOOT_EXTERNAL_LAYOUT_DELETED", {
                    formatArgs = { currentProfile },
                    onAccept = function()
                        ReloadUI()
                    end,
                })
            end
        end)
    end
end

function Profiles:OnPlayerSpecChanged(opts)
    opts = opts or {}
    if not self:IsSpecProfilesEnabled() then
        return
    end
    -- Spec Profiles should ONLY react to an actual spec change mid-session.
    -- Do NOT auto-switch on login/reload, otherwise it can override a manual
    -- profile switch that intentionally required a reload to establish baselines.
    if opts.fromLogin then
        return
    end
    local specID = getCurrentSpecID()
    if not specID then
        return
    end

    -- Only react to an actual spec change mid-session. Loading screens and other
    -- incidental triggers can run this path without a spec change; those must not
    -- prompt/reload simply due to a spec/profile mismatch.
    if self._lastKnownSpecID and specID == self._lastKnownSpecID then
        return
    end
    -- Genuine spec change detected - record it immediately even if no assignment exists.
    self._lastKnownSpecID = specID

    local targetProfile = self:GetSpecAssignment(specID)
    if not targetProfile then
        return
    end
    if addon.db:GetCurrentProfile() == targetProfile then
        return
    end
    if not self._layoutLookup[targetProfile] then
        return
    end

    -- Combat guard: defer reload until combat ends.
    if InCombatLockdown and InCombatLockdown() then
        self._pendingSpecReload = { profile = targetProfile, specID = specID }
        return
    end

    local specName = (GetSpecializationNameByID and GetSpecializationNameByID(specID)) or "unknown"
    -- ReloadUI() is protected unless triggered by a hardware event. Spec change events are not.
    -- So we prompt a one-click dialog and perform ReloadUI() from the click handler.
    self:PromptReloadToProfile(targetProfile, { reason = "SpecChanged", specID = specID, specName = specName })
end

function Profiles:GetSpecOptions()
    local options = {}
    if type(GetNumSpecializations) ~= "function" then
        return options
    end
    local total = GetNumSpecializations() or 0
    for index = 1, total do
        local specID, specName, _, specIcon = GetSpecializationInfo(index)
        if specID then
            table.insert(options, {
                specIndex = index,
                specID = specID,
                name = specName or ("Spec " .. tostring(index)),
                icon = specIcon,
            })
        end
    end
    return options
end
