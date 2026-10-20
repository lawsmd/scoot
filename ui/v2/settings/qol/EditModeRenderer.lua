-- EditModeRenderer.lua - Quality of Life: Edit Mode settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.QoL = addon.UI.Settings.QoL or {}
addon.UI.Settings.QoL.EditMode = {}

local EditMode = addon.UI.Settings.QoL.EditMode
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- DB Helpers
--------------------------------------------------------------------------------

-- Each addon sets addon.QoLHost in its own host file (core/qolhost.lua,
-- forever/qualityoflife/host.lua).
local function getSetting(key)
    return addon.QoLHost.Get(key)
end

local function setSetting(key, value)
    addon.QoLHost.Set(key, value)
end

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function EditMode.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:AddToggle({
        label = "Show Nudge Arrows",
        description = "Display clickable arrow buttons on the edges of selected Edit Mode frames for pixel-by-pixel positioning. Shift+click moves 10px.",
        get = function()
            return getSetting("editModeNudgeArrows") or false
        end,
        set = function(value)
            setSetting("editModeNudgeArrows", value)
            if addon.EditMode and addon.EditMode.SetNudgeArrowsEnabled then
                addon.EditMode.SetNudgeArrowsEnabled(value)
            end
        end,
    })

    builder:AddToggle({
        label = "Enable Sub-Grid",
        description = "When Blizzard's Show Grid is active, display a finer 10x10 sub-grid within each grid block for precise alignment.",
        get = function()
            return getSetting("editModeSubGrid") or false
        end,
        set = function(value)
            setSetting("editModeSubGrid", value)
            if addon.EditMode and addon.EditMode.SetSubGridEnabled then
                addon.EditMode.SetSubGridEnabled(value)
            end
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Register Renderer
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("qolEditMode", function(panel, scrollContent)
    EditMode.Render(panel, scrollContent)
end)

return EditMode
