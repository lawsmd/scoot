--------------------------------------------------------------------------------
-- forever/qualityoflife/miscpage.lua
-- The Misc page under Quality of Life: the conveniences too small for a page
-- of their own. Today, the place of Blizzard's error and quest progress text
-- (messages.lua), whose row the Current Objectives page draws a second time.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Messages = addon.QualityOfLife.Messages
local SettingsBuilder = addon.UI.SettingsBuilder

local NAV_KEY = Messages.NAV_KEY

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    builder:AddCollapsibleSection({ title = "Error & Quest Text", componentId = NAV_KEY,
        sectionKey = "messages", defaultExpanded = true,
        buildContent = function(_, inner)
            Messages.AddPositionRow(inner, { other = "the Current Objectives page" })
            Messages.AddHideErrorsRow(inner)
            inner:Finalize()
        end })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, Render)
