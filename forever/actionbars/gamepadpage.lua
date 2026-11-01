--------------------------------------------------------------------------------
-- forever/actionbars/gamepadpage.lua
-- The Gamepad Bars page under the Action Bars group: a Layout section with
-- the replica's switch, Scale and Blizzard's five Edit Mode settings for
-- the gamepad bar, and a Visibility section with the action bars'
-- Visibility rows (page.lua) for its token. Off the gamepad UI the page
-- says so and draws nothing else: the bar is built there alone.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local GamepadBar = ActionBars.GamepadBar
local DB = addon.DB
local SettingsBuilder = addon.UI.SettingsBuilder

local Page = {}
GamepadBar.Page = Page

local NAV_KEY = GamepadBar.NAV_KEY

local activeBuilder -- the page's builder while it is drawn
local quiet = false -- a page control is mid-edit

-- As stancepage.lua's: the refresh GamepadBar.Apply asks for is refused
-- while the page itself writes.
local function edit(fn)
    quiet = true
    local ok, err = pcall(fn)
    quiet = false
    if not ok then error(err, 0) end
end

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    activeBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    if not ActionBars.IsEnabled() then
        builder:AddDescription("Action Bars is off on the Features page.")
        builder:Finalize()
        return
    end

    local Gamepad = addon.Gamepad
    if not (Gamepad and Gamepad.IsActive and Gamepad.IsActive()) then
        builder:AddDescription("The gamepad bar draws under Forever's gamepad UI. This session is on mouse and keyboard.")
        builder:Finalize()
        return
    end

    local function get(field) return function() return GamepadBar.Get(field) end end
    local function toggleGet(field, default)
        return function()
            local v = GamepadBar.Get(field)
            if v == nil then return default end
            return v == true
        end
    end
    local function set(field)
        return function(v)
            edit(function() GamepadBar.Set(field, v) end)
        end
    end

    builder:AddCollapsibleSection({
        title = "Layout", componentId = NAV_KEY, sectionKey = "layout",
        defaultExpanded = true,
        buildContent = function(_, inner)
            inner:AddToggle({ label = "Replace the Gamepad Bar",
                description = "Takes effect after a reload.",
                get = toggleGet("enabled", true),
                set = function(v)
                    edit(function() DB.Set(GamepadBar.PATH .. "enabled", v and true or false) end)
                end })
            local range = GamepadBar.RANGES.scale
            inner:AddSlider({ label = "Scale", min = range.min, max = range.max, step = range.step, precision = 0,
                minLabel = range.min .. "%", maxLabel = range.max .. "%", displaySuffix = "%",
                get = get("scale"), set = set("scale") })
            inner:AddToggle({ label = "Compact", get = toggleGet("compact", false), set = set("compact") })
            inner:AddToggle({ label = "Show Empty Bars", get = toggleGet("showEmptyBars", true),
                set = set("showEmptyBars") })
            inner:AddToggle({ label = "Highlight", get = toggleGet("highlight", true), set = set("highlight") })
            inner:AddToggle({ label = "Expand Active Bar", get = toggleGet("expand", true), set = set("expand") })
            inner:AddToggle({ label = "Button Prompts", get = toggleGet("buttonPrompts", false),
                set = set("buttonPrompts") })
            inner:Finalize()
        end,
    })

    builder:AddCollapsibleSection({
        title = "Visibility", componentId = NAV_KEY, sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(_, inner)
            ActionBars.Page.VisibilityRows(inner, GamepadBar.KEY)
        end,
    })

    builder:Finalize()
end

--- After a change the page did not ask for (a profile switch while it is
--- open): re-render when the panel shows this page.
function Page.Refresh()
    if quiet or not activeBuilder then return end
    local panel = addon.UI.SettingsPanel
    local shown = panel and panel.frame and panel.frame:IsShown()
    if shown and panel._currentBuilder == activeBuilder then
        activeBuilder:DeferredRefreshAll()
    end
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, function(panel, scrollContent)
    Render(panel, scrollContent)
end)
