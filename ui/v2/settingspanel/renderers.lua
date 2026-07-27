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

-- Debug Menu (inline renderer)

UIPanel:RegisterRenderer("debugMenu", function(self, scrollContent)
    local Controls = addon.UI.Controls
    local Theme = addon.UI.Theme

    self._debugMenuControls = self._debugMenuControls or {}
    for _, ctrl in ipairs(self._debugMenuControls) do
        if ctrl.Cleanup then ctrl:Cleanup() end
        if ctrl.Hide then ctrl:Hide() end
        if ctrl.SetParent then ctrl:SetParent(nil) end
    end
    self._debugMenuControls = {}

    local headerLabel = scrollContent:CreateFontString(nil, "OVERLAY")
    Theme:ApplyLabelFont(headerLabel, 14)
    headerLabel:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, 0)
    headerLabel:SetText("Developer Testing Tools")
    local ar, ag, ab = Theme:GetAccentColor()
    headerLabel:SetTextColor(ar, ag, ab, 1)
    table.insert(self._debugMenuControls, headerLabel)

    local yOffset = -30

    local descLabel = scrollContent:CreateFontString(nil, "OVERLAY")
    Theme:ApplyValueFont(descLabel, 11)
    descLabel:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    descLabel:SetPoint("RIGHT", scrollContent, "RIGHT", -20, 0)
    descLabel:SetText("These options are for addon development and testing. Use with caution.")
    descLabel:SetTextColor(0.7, 0.7, 0.7, 1)
    descLabel:SetJustifyH("LEFT")
    descLabel:SetWordWrap(true)
    table.insert(self._debugMenuControls, descLabel)

    yOffset = yOffset - 50

    local secretCVars = {
        "secretCombatRestrictionsForced",
        "secretChallengeModeRestrictionsForced",
        "secretEncounterRestrictionsForced",
        "secretMapRestrictionsForced",
        "secretPvPMatchRestrictionsForced",
    }

    local toggle = Controls:CreateToggle({
        parent = scrollContent,
        label = "Force Secret Restrictions",
        description = "Enables all secret restriction CVars to simulate combat/instance restrictions for testing taint behavior.",
        get = function()
            local val = GetCVar("secretCombatRestrictionsForced")
            return val == "1"
        end,
        set = function(enabled)
            local newVal = enabled and "1" or "0"
            for _, cvar in ipairs(secretCVars) do
                pcall(SetCVar, cvar, newVal)
            end
        end,
    })
    toggle:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    toggle:SetPoint("RIGHT", scrollContent, "RIGHT", 0, 0)
    table.insert(self._debugMenuControls, toggle)

    yOffset = yOffset - 70

    local bugSackToggle = Controls:CreateToggle({
        parent = scrollContent,
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
    bugSackToggle:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    bugSackToggle:SetPoint("RIGHT", scrollContent, "RIGHT", 0, 0)
    table.insert(self._debugMenuControls, bugSackToggle)

    yOffset = yOffset - 70

    --------------------------------------------------------------------------
    -- TEMP: Roster Overlay diagnostics
    --------------------------------------------------------------------------
    -- Remove this whole block once the blank-rows investigation is closed.
    -- These exist because the overlay wraps every name transfer in pcall, so a
    -- failure is completely silent, and because chat is disabled on ScooterDeck
    -- -- output has to land in the copyable dialog, not in a print().
    --------------------------------------------------------------------------

    local tempHeader = scrollContent:CreateFontString(nil, "OVERLAY")
    Theme:ApplyLabelFont(tempHeader, 13)
    tempHeader:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    tempHeader:SetText("TEMP - Roster Overlay")
    tempHeader:SetTextColor(ar, ag, ab, 1)
    table.insert(self._debugMenuControls, tempHeader)

    yOffset = yOffset - 24

    local tempDesc = scrollContent:CreateFontString(nil, "OVERLAY")
    Theme:ApplyValueFont(tempDesc, 11)
    tempDesc:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    tempDesc:SetPoint("RIGHT", scrollContent, "RIGHT", -20, 0)
    tempDesc:SetText("Run these while in a raid group. Output opens in a copyable window. Temporary - will be removed.")
    tempDesc:SetTextColor(0.7, 0.7, 0.7, 1)
    tempDesc:SetJustifyH("LEFT")
    tempDesc:SetWordWrap(true)
    table.insert(self._debugMenuControls, tempDesc)

    yOffset = yOffset - 40

    local debugButtons = {
        {
            text = "Probe Raid Name Frames",
            fn = function()
                if addon.DebugRosterOverlay then
                    addon.DebugRosterOverlay()
                elseif addon.DebugShowWindow then
                    addon.DebugShowWindow("Roster Overlay Probe",
                        "Probe module not loaded.\n\nThis needs a full client restart, not a /reload -- it was added as a new .toc entry.")
                end
            end,
        },
        {
            text = "Dump Overlay Row State",
            fn = function()
                if addon.DebugRosterOverlayRows then
                    addon.DebugRosterOverlayRows()
                elseif addon.DebugShowWindow then
                    addon.DebugShowWindow("Roster Overlay Rows",
                        "Probe module not loaded.\n\nThis needs a full client restart, not a /reload -- it was added as a new .toc entry.")
                end
            end,
        },
    }

    for _, spec in ipairs(debugButtons) do
        local btn = Controls:CreateButton({
            parent = scrollContent,
            text = spec.text,
            width = 220,
            onClick = spec.fn,
        })
        if btn then
            btn:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
            table.insert(self._debugMenuControls, btn)
            yOffset = yOffset - 34
        end
    end

    yOffset = yOffset - 20

    scrollContent:SetHeight(math.abs(yOffset) + 20)
end)
