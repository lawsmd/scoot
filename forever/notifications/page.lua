--------------------------------------------------------------------------------
-- forever/notifications/page.lua
-- The Notifications page under Quality of Life: the look and the motion every
-- notification shares (notifications.lua). The emphasized row at the top
-- lists the features able to send one, read off the source registry, so the
-- list is whatever has registered. Each feature's own switch and options are
-- in its own section, which links back here.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Notifications = addon.Notifications
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers

local NAV_KEY = Notifications.NAV_KEY

-- The text block's fields against the stored keys.
local TEXT_MAP = { fontFace = "fontFace", style = "fontStyle", size = "size" }

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    builder:AddInfoRow({
        label = "Notification Sources",
        infoIcon = {
            tooltipTitle = "Notification Sources",
            tooltipText = Notifications.SourcesText(),
        },
    })

    -- Notifications.Set applies on its own, so the block takes no apply.
    local get, set = Helpers.CreateFlatAccessors(Notifications.Get, Notifications.Set, TEXT_MAP)
    local _, objectSize = Notifications.FontDefaults()
    local size = Notifications.SIZE
    builder:AddTextStyleBlock({
        get = get, set = set,
        defaults = { style = "THICKOUTLINE", size = objectSize },
        style = { label = "Font Style", order = Helpers.fontStyleOrderPaired },
        size = { min = size.min, max = size.max, step = size.step,
                 minLabel = tostring(size.min), maxLabel = tostring(size.max) },
        color = false,
        offset = false,
    })

    builder:AddSelector({ label = "Direction",
        values = Notifications.DIRECTIONS.values, order = Notifications.DIRECTIONS.order,
        get = Notifications.Direction,
        set = function(v) Notifications.Set("direction", v) end })

    local hold = Notifications.HOLD
    builder:AddSlider({ label = "Hold Time",
        min = hold.min, max = hold.max, step = hold.step, precision = 1,
        minLabel = hold.min .. "s", maxLabel = hold.max .. "s",
        get = Notifications.Hold,
        set = function(v) Notifications.Set("hold", tonumber(v) or hold.default) end })

    -- Forever only (display.lua): retail draws the page with no toast to play.
    if Notifications.ShowTest then
        builder:AddButtonRow({ buttons = {
            { text = "Show Test Notification",
              onClick = function() Notifications.ShowTest() end,
              isDisabled = function() return not Notifications.AnyEnabled() end },
        } })
    end

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, Render)
