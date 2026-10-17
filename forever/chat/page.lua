--------------------------------------------------------------------------------
-- forever/chat/page.lua
-- The Chat page, under Interface in forever/menu.lua: the window, its text,
-- its tabs, the fade, the formatting switches and the alerts. Loads on
-- retail too, where no holder is built: the controls still draw and write.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CR = addon.ChatReplica
local Style = CR.Style
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers

local NAV_KEY = CR.NAV_KEY

local function apply()
    Style.Apply()
end

local function getSetting(key)
    return Style.Get(key)
end

local function setSetting(key, value)
    Style.Set(key, value)
    apply()
end

-- A switch that changes what a line shows: every window is rebuilt from its
-- source, so the lines already on screen take it too.
local function setFormatting(key, value)
    Style.Set(key, value)
    if CR.Display and CR.Display.ResyncAll then CR.Display.ResyncAll() end
end

local EDIT_BOX_POSITION = {
    values = { below = "Below the Window", above = "Above the Tabs" },
    order = { "below", "above" },
}
local SHOW_TABS = {
    values = { always = "Always", mouseover = "On Mouseover" },
    order = { "always", "mouseover" },
}
local TAB_FLASH = {
    values = { all = "Every Window", whispers = "Whispers Only", never = "Never" },
    order = { "all", "whispers", "never" },
}

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    local function rerender()
        C_Timer.After(0.05, function()
            if panel then Render(panel, scrollContent) end
        end)
    end

    ----------------------------------------------------------------------------
    -- Window
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Window",
        componentId = NAV_KEY,
        sectionKey = "window",
        defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSlider({
                label = "Width",
                min = Style.WIDTH.min, max = Style.WIDTH.max, step = Style.WIDTH.step,
                get = Style.Width,
                set = function(v) setSetting("width", Style.Clamp(v, Style.WIDTH)) end,
                minLabel = tostring(Style.WIDTH.min), maxLabel = tostring(Style.WIDTH.max),
            })
            inner:AddSlider({
                label = "Height",
                min = Style.HEIGHT.min, max = Style.HEIGHT.max, step = Style.HEIGHT.step,
                get = Style.Height,
                set = function(v) setSetting("height", Style.Clamp(v, Style.HEIGHT)) end,
                minLabel = tostring(Style.HEIGHT.min), maxLabel = tostring(Style.HEIGHT.max),
            })
            inner:AddSlider({
                label = "Scale",
                min = Style.SCALE.min, max = Style.SCALE.max, step = Style.SCALE.step,
                get = Style.ScalePercent,
                set = function(v) setSetting("scale", Style.Clamp(v, Style.SCALE)) end,
                minLabel = "50%", maxLabel = "200%",
            })
            inner:AddSlider({
                label = "Background Opacity",
                description = "The window's background and border. The game's own window alpha is the starting value.",
                min = Style.BACKGROUND_OPACITY.min, max = Style.BACKGROUND_OPACITY.max, step = Style.BACKGROUND_OPACITY.step,
                get = function() return math.floor(Style.BackgroundOpacity() * 100 + 0.5) end,
                set = function(v) setSetting("backgroundOpacity", Style.Clamp(v, Style.BACKGROUND_OPACITY)) end,
                minLabel = "0%", maxLabel = "100%",
            })
            inner:AddSelector({
                label = "Edit Box Position",
                values = EDIT_BOX_POSITION.values, order = EDIT_BOX_POSITION.order,
                get = function() return Style.EditBoxAbove() and "above" or "below" end,
                set = function(v) setSetting("editBoxPosition", v == "above" and "above" or "below") end,
            })
            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Text
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = NAV_KEY,
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(_, inner)
            local get, set = Helpers.CreateFlatAccessors(getSetting, Style.Set, {
                fontFace = "fontFace",
                style = "fontStyle",
                size = "fontSize",
            })
            -- The lines are engine-fed strings the message frame pools, so
            -- the unpaired style list: Deep Shadow has no copy to draw on.
            inner:AddTextStyleBlock({
                get = function(field)
                    if field == "size" then return Style.FontSize() end
                    return get(field)
                end,
                set = set, apply = apply,
                defaults = { fontFace = "FRIZQT__", style = "SHADOW", size = Style.FontSize() },
                font = { description = "The font of every line, and of the edit box." },
                style = { order = addon.FontStyles.order },
                size = { min = Style.FONT_SIZE.min, max = Style.FONT_SIZE.max,
                    minLabel = tostring(Style.FONT_SIZE.min), maxLabel = tostring(Style.FONT_SIZE.max),
                    description = "The game's own size for each window is the starting value; the tab menu sets it per window." },
                color = false,
                offset = false,
            })
            inner:AddToggle({
                label = "Fade Lines",
                description = "Lines fade out after a while, as the game's own windows do.",
                get = function() return getSetting("fadeLines") == true end,
                set = function(v)
                    setSetting("fadeLines", v and true or false)
                    rerender()
                end,
            })
            inner:AddSlider({
                label = "Time Visible",
                min = Style.TIME_VISIBLE.min, max = Style.TIME_VISIBLE.max, step = Style.TIME_VISIBLE.step,
                get = Style.TimeVisible,
                set = function(v) setSetting("timeVisible", Style.Clamp(v, Style.TIME_VISIBLE)) end,
                minLabel = "10s", maxLabel = "600s",
                isDisabled = function() return getSetting("fadeLines") ~= true end,
            })
            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Tabs
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Tabs",
        componentId = NAV_KEY,
        sectionKey = "tabs",
        defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSelector({
                label = "Show Tabs",
                values = SHOW_TABS.values, order = SHOW_TABS.order,
                get = function() return getSetting("showTabs") == "mouseover" and "mouseover" or "always" end,
                set = function(v) setSetting("showTabs", v == "mouseover" and "mouseover" or "always") end,
            })
            inner:AddSelector({
                label = "Flash Tabs",
                description = "Flash a tab when a line lands in a window that is not selected.",
                values = TAB_FLASH.values, order = TAB_FLASH.order,
                get = function() return getSetting("tabFlash") or "all" end,
                set = function(v) setSetting("tabFlash", v) end,
            })
            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Fade
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Fade",
        componentId = NAV_KEY,
        sectionKey = "fade",
        defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddToggle({
                label = "Idle Fade",
                description = "The background and border fade out when the mouse has been away from the window for the delay below, and back on the next mouseover.",
                get = function() return getSetting("idleFade") == true end,
                set = function(v)
                    setSetting("idleFade", v and true or false)
                    rerender()
                end,
            })
            inner:AddSlider({
                label = "Idle Fade Delay",
                min = Style.IDLE_FADE_DELAY.min, max = Style.IDLE_FADE_DELAY.max, step = Style.IDLE_FADE_DELAY.step,
                get = Style.IdleFadeDelay,
                set = function(v) setSetting("idleFadeDelay", Style.Clamp(v, Style.IDLE_FADE_DELAY)) end,
                minLabel = "1s", maxLabel = "60s",
                isDisabled = function() return getSetting("idleFade") ~= true end,
            })
            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Formatting
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Formatting",
        componentId = NAV_KEY,
        sectionKey = "formatting",
        defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddToggle({
                label = "Class-Colored Names",
                description = "Color every name by its class, in every channel. This is the game's own option, so it applies in instances too.",
                get = Style.ClassColors,
                set = function(v)
                    Style.SetClassColors(v)
                    apply()
                end,
            })
            inner:AddToggle({
                label = "Short Channel Labels",
                description = "[Guild] becomes [G], [1. General] becomes [1], and so on. A line the game keeps secret in an instance shows its full label.",
                get = function() return getSetting("shortLabels") == true end,
                set = function(v) setFormatting("shortLabels", v and true or false) end,
            })
            local values, order = Style.TimestampOptions()
            inner:AddSelector({
                label = "Timestamps",
                description = "The game's own timestamp option, which stamps every line.",
                values = values, order = order,
                get = Style.Timestamps,
                set = function(v)
                    Style.SetTimestamps(v)
                    apply()
                    rerender()
                end,
            })
            inner:AddToggleColorPicker({
                label = "Color Timestamps",
                get = function() return getSetting("colorTimestamps") == true end,
                set = function(v) setFormatting("colorTimestamps", v and true or false) end,
                getColor = function() return Style.Color("timestampColor", Style.TIMESTAMP_COLOR) end,
                setColor = function(r, g, b, a)
                    setFormatting("timestampColor", { r, g, b, a })
                end,
                hasAlpha = false,
                isDisabled = function() return Style.Timestamps() == "none" end,
            })
            inner:AddToggle({
                label = "Clickable Links",
                description = "A web address in a line becomes a link; a click opens a box to copy it from.",
                get = function() return getSetting("urlLinks") == true end,
                set = function(v) setFormatting("urlLinks", v and true or false) end,
            })
            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Alerts
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Alerts",
        componentId = NAV_KEY,
        sectionKey = "alerts",
        defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddToggle({
                label = "Mention Highlight",
                description = "Your name in gold when someone says it. A line the game keeps secret in an instance is not searched.",
                get = function() return getSetting("mentionHighlight") == true end,
                set = function(v)
                    setFormatting("mentionHighlight", v and true or false)
                    rerender()
                end,
            })
            inner:AddToggle({
                label = "Mention Sound",
                description = "The whisper sound when your name is mentioned.",
                get = function() return getSetting("mentionSound") == true end,
                set = function(v) setSetting("mentionSound", v and true or false) end,
                isDisabled = function() return getSetting("mentionHighlight") ~= true end,
            })
            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, Render)
