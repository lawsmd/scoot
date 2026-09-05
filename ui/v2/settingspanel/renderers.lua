-- settingspanel/renderers.lua - Renderer registry with self-registration support
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel

-- Renderer Registry
-- Renderer files self-register via RegisterRenderer() at load time.

UIPanel._renderers = {}

function UIPanel:RegisterRenderer(key, renderFn)
    self._renderers[key] = renderFn
end

--------------------------------------------------------------------------------
-- Debug Menu (inline renderer)
--------------------------------------------------------------------------------
-- Developer tools only. The UFZ Player/Target production previews that used to
-- live here shipped: they are the real pages now (ui/v2/unitframes/
-- UFZSections.lua, nav keys ufzPlayer/ufzTarget), driving the promoted engine
-- in core/components/unitframesz/.
--------------------------------------------------------------------------------

local function RenderDebugMenu(panel, scrollContent)
    panel:ClearContent()

    local SettingsBuilder = addon.UI.SettingsBuilder

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function()
        RenderDebugMenu(panel, scrollContent)
    end)

    builder:AddSection("Developer Tools")

    local secretCVars = {
        "secretCombatRestrictionsForced",
        "secretChallengeModeRestrictionsForced",
        "secretEncounterRestrictionsForced",
        "secretMapRestrictionsForced",
        "secretPvPMatchRestrictionsForced",
    }

    builder:AddToggle({
        label = "Force Secret Restrictions",
        description = "Enables all secret restriction CVars to simulate combat/instance restrictions for testing.",
        get = function()
            local val = GetCVar("secretCombatRestrictionsForced")
            return val == "1"
        end,
        set = function(enabled)
            local newVal = enabled and "1" or "0"
            for _, cvar in ipairs(secretCVars) do
                -- Kept off core/profiles/cvars.lua: loops a debug CVar list with a caller-supplied value.
                pcall(SetCVar, cvar, newVal)
            end
        end,
    })

    builder:AddToggle({
        label = "Keep BugSack Button Separate",
        description = "Keep BugSack's minimap button visible outside the addon button container.",
        get = function()
            return addon.db and addon.db.profile and addon.db.profile.bugSackButtonSeparate
        end,
        set = function(enabled)
            if addon.db and addon.db.profile then
                addon.db.profile.bugSackButtonSeparate = enabled
                local minimapComp = addon.Components and addon.Components["minimapStyle"]
                if minimapComp and minimapComp.ApplyStyling then
                    minimapComp:ApplyStyling()
                end
            end
        end,
    })

    builder:Finalize()
end

UIPanel:RegisterRenderer("debugMenu", RenderDebugMenu)
