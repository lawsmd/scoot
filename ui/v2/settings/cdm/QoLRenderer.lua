-- QoLRenderer.lua - CDM Quality of Life settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.CDM = addon.UI.Settings.CDM or {}
addon.UI.Settings.CDM.QoL = {}

local QoL = addon.UI.Settings.CDM.QoL
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function QoL.Render(panel, scrollContent)
    panel:ClearContent()

    -- CVar helpers (local to this render)
    local function getCooldownViewerEnabledFromCVar()
        local v
        if C_CVar and C_CVar.GetCVar then
            v = C_CVar.GetCVar("cooldownViewerEnabled")
        elseif GetCVar then
            v = GetCVar("cooldownViewerEnabled")
        end
        return (v == "1") or false
    end

    -- Profile data helpers
    local function getProfileQoL()
        local profile = addon and addon.db and addon.db.profile
        return profile and profile.cdmQoL
    end

    local function ensureProfileQoL()
        if not (addon and addon.db and addon.db.profile) then return nil end
        addon.db.profile.cdmQoL = addon.db.profile.cdmQoL or {}
        return addon.db.profile.cdmQoL
    end

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:AddToggle({
        label = "Enable Cooldown Manager",
        description = "Show or hide the Cooldown Manager on this profile. Overrides Blizzard's per-character setting in Options > Gameplay > Combat.",
        get = function()
            local q = getProfileQoL()
            if q and q.enableCDM ~= nil then
                return q.enableCDM
            end
            return getCooldownViewerEnabledFromCVar()
        end,
        set = function(value)
            local q = ensureProfileQoL()
            if not q then return end
            q.enableCDM = value
            if addon.ApplyCooldownViewerEnabled then
                addon.ApplyCooldownViewerEnabled("toggle")
            end
            -- If enabling, apply stored CDM styling
            if value and addon and addon.ApplyStyles then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if addon and addon.ApplyStyles then
                            addon:ApplyStyles()
                        end
                    end)
                else
                    addon:ApplyStyles()
                end
            end
        end,
    })

    builder:AddToggle({
        label = "Enable /cdm command",
        description = "Type /cdm to quickly open the Cooldown Manager settings menu.",
        get = function()
            local q = getProfileQoL()
            return (q and q.enableSlashCDM) or false
        end,
        set = function(value)
            local q = ensureProfileQoL()
            if not q then return end
            q.enableSlashCDM = value
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Return module
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("cdmQoL", function(panel, scrollContent)
    QoL.Render(panel, scrollContent)
end)

return QoL
