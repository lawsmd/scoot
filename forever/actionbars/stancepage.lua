--------------------------------------------------------------------------------
-- forever/actionbars/stancepage.lua
-- The Stance Bar page under the Action Bars group: a Layout section with
-- Blizzard's four Edit Mode settings for the stance bar plus the two flow directions, and a Visibility
-- section with the action bars' Visibility rows (page.lua) for its token.
-- Configure on the bar's Edit Mode box opens this page (stance.lua, the
-- brand).
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local Stance = ActionBars.Stance
local SettingsBuilder = addon.UI.SettingsBuilder

local Page = {}
Stance.Page = Page

local NAV_KEY = Stance.NAV_KEY

local activeBuilder -- the page's builder while it is drawn
local quiet = false -- a page control is mid-edit

-- As microbagspage.lua's: the refresh Stance.Apply asks for is refused while
-- the page itself writes.
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

    local function get(field) return function() return Stance.Get(field) end end
    local function set(field)
        return function(v)
            edit(function() Stance.Set(field, v) end)
        end
    end
    local function slider(inner, label, range, field, percent)
        inner:AddSlider({ label = label, min = range.min, max = range.max, step = range.step, precision = 0,
            minLabel = range.min .. (percent and "%" or ""), maxLabel = range.max .. (percent and "%" or ""),
            displaySuffix = percent and "%" or nil, get = get(field), set = set(field) })
    end

    builder:AddCollapsibleSection({
        title = "Layout", componentId = NAV_KEY, sectionKey = "layout",
        defaultExpanded = true,
        buildContent = function(_, inner)
            inner:AddSelector({ label = "Orientation", values = Stance.ORIENTATION_VALUES,
                order = Stance.ORIENTATION_ORDER, get = get("orientation"), set = set("orientation") })
            slider(inner, "Rows", Stance.RANGES.lines, "lines")
            slider(inner, "Icon Size", Stance.RANGES.iconSize, "iconSize", true)
            slider(inner, "Icon Padding", Stance.RANGES.iconPadding, "iconPadding")
            inner:AddSelector({ label = "Horizontal Flow", values = Stance.FLOW_X_VALUES,
                order = Stance.FLOW_X_ORDER, get = get("flowX"), set = set("flowX") })
            inner:AddSelector({ label = "Vertical Flow", values = Stance.FLOW_Y_VALUES,
                order = Stance.FLOW_Y_ORDER, get = get("flowY"), set = set("flowY") })
            inner:Finalize()
        end,
    })

    builder:AddCollapsibleSection({
        title = "Visibility", componentId = NAV_KEY, sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(_, inner)
            ActionBars.Page.VisibilityRows(inner, Stance.KEY)
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
