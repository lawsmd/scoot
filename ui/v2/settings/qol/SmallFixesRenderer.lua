-- SmallFixesRenderer.lua - Quality of Life: Small Fixes settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.QoL = addon.UI.Settings.QoL or {}
addon.UI.Settings.QoL.SmallFixes = {}

local SmallFixes = addon.UI.Settings.QoL.SmallFixes
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- DB Helpers
--------------------------------------------------------------------------------

local function getQoL()
    local profile = addon and addon.db and addon.db.profile
    return profile and profile.qol
end

local MODIFIER_SETTING = {
    shift = "modifierTargetShift",
    ctrl  = "modifierTargetCtrl",
    alt   = "modifierTargetAlt",
}

local function getModifier(mod)
    local q = getQoL()
    return (q and q[MODIFIER_SETTING[mod]]) or false
end

local function setModifier(mod, value)
    if addon.SmallFixes and addon.SmallFixes.SetModifierTargetEnabled then
        addon.SmallFixes.SetModifierTargetEnabled(mod, value)
    end
end

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function SmallFixes.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:AddMultiToggleRow({
        label = "Modifier + Left-Click Targeting",
        description = "Restores targeting when you hold Shift, Ctrl or Alt and left-click a unit frame. "
            .. "Game patch 12.0.7 stopped routing modified left-clicks to targeting. "
            .. "Covers Blizzard unit frames and Scoot unit frames, not nameplates. Changes apply out of combat.",
        toggles = {
            {
                key = "shift",
                label = "Shift",
                get = function() return getModifier("shift") end,
                set = function(value) setModifier("shift", value) end,
            },
            {
                key = "ctrl",
                label = "Ctrl",
                get = function() return getModifier("ctrl") end,
                set = function(value) setModifier("ctrl", value) end,
            },
            {
                key = "alt",
                label = "Alt",
                get = function() return getModifier("alt") end,
                set = function(value) setModifier("alt", value) end,
            },
        },
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Register Renderer
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("qolSmallFixes", function(panel, scrollContent)
    SmallFixes.Render(panel, scrollContent)
end)

return SmallFixes
