--------------------------------------------------------------------------------
-- forever/actionbars/microbagspage.lua
-- The Micro & Bag page under the Action Bars group: the Style at the top,
-- then a section for the micro menu and one for the bag bar. A Style or
-- orientation write changes which rows apply, so it re-renders; the bag
-- bar's layout rows stand disabled under the combined style, where the micro
-- menu's rows lay out the whole line. Configure on an anchor's box opens
-- this page with that bar's section expanded (microbags.lua, the brand).
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local MicroBags = ActionBars.MicroBags
local SettingsBuilder = addon.UI.SettingsBuilder

local Page = {}
MicroBags.Page = Page

local NAV_KEY = MicroBags.NAV_KEY
local SECTION_KEYS = MicroBags.SECTION_KEYS

-- The bag slot grid, by row: the four bags, then the fixed slots.
local GRID_COLUMNS = 4
local GRID_ORDER = { "bag1", "bag2", "bag3", "bag4", "backpack", "reagent", "keyring" }

local activeBuilder -- the page's builder while it is drawn
local quiet = false -- a page control is mid-edit

-- As page.lua's: the refresh MicroBags.Apply asks for is refused while the
-- page itself writes, and a structural write re-renders a frame later.
local function edit(builder, fn, structural)
    quiet = true
    local ok, err = pcall(fn)
    quiet = false
    if not ok then error(err, 0) end
    if structural then builder:DeferredRefreshAll() end
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

    local function get(field) return function() return MicroBags.Get(field) end end
    local function set(field, structural)
        return function(v)
            edit(builder, function() MicroBags.Set(field, v) end, structural)
        end
    end
    local function combined() return MicroBags.Style() == "combined" end

    builder:AddSelector({ label = "Style", emphasized = true,
        values = MicroBags.STYLE_VALUES, order = MicroBags.STYLE_ORDER,
        get = get("style"), set = set("style", true) })

    builder:AddCollapsibleSection({
        title = "Micro Menu", componentId = NAV_KEY, sectionKey = SECTION_KEYS.micro,
        defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSelector({ label = "Orientation", values = MicroBags.ORIENTATION_VALUES,
                order = MicroBags.ORIENTATION_ORDER, get = get("micro.orientation"), set = set("micro.orientation") })
            inner:AddSelector({ label = "Order", values = MicroBags.ORDER_VALUES, order = MicroBags.ORDER_ORDER,
                get = get("micro.order"), set = set("micro.order") })
            local r = MicroBags.RANGES.microSize
            inner:AddSlider({ label = "Size", min = r.min, max = r.max, step = r.step, precision = 0,
                minLabel = r.min .. "%", maxLabel = r.max .. "%", displaySuffix = "%",
                get = get("micro.size"), set = set("micro.size") })
            inner:Finalize()
        end,
    })

    builder:AddCollapsibleSection({
        title = "Bag Bar", componentId = NAV_KEY, sectionKey = SECTION_KEYS.bags,
        defaultExpanded = false,
        buildContent = function(_, inner)
            local vertical = MicroBags.Get("bags.orientation") == "vertical"
            local dirValues, dirOrder = MicroBags.DirectionChoices(vertical)
            inner:AddSelector({ label = "Orientation", values = MicroBags.ORIENTATION_VALUES,
                order = MicroBags.ORIENTATION_ORDER, isDisabled = combined,
                get = get("bags.orientation"), set = set("bags.orientation", true) })
            inner:AddSelector({ label = "Direction", values = dirValues, order = dirOrder, isDisabled = combined,
                get = get("bags.direction"), set = set("bags.direction") })
            local size = MicroBags.RANGES.bagsSize
            inner:AddSlider({ label = "Size", min = size.min, max = size.max, step = size.step, precision = 0,
                minLabel = size.min .. "%", maxLabel = size.max .. "%", displaySuffix = "%", isDisabled = combined,
                get = get("bags.size"), set = set("bags.size") })
            local pad = MicroBags.RANGES.padding
            inner:AddSlider({ label = "Bag Slot Padding", min = pad.min, max = pad.max, step = pad.step,
                precision = 0, isDisabled = combined, get = get("bags.padding"), set = set("bags.padding") })

            local Bags = MicroBags.Bags
            local labels = {}
            for _, slot in ipairs(Bags and Bags.SLOTS or {}) do labels[slot.key] = slot.label end
            local items = {}
            for _, key in ipairs(GRID_ORDER) do
                if labels[key] then
                    items[#items + 1] = {
                        key = key, label = labels[key],
                        get = function() return MicroBags.SlotShown(key) end,
                        set = set("slots." .. key .. ".shown"),
                        isDisabled = key == "keyring" and function() return not Bags.HasKeyring() end or nil,
                    }
                end
            end
            inner:AddCheckboxGrid({ label = "Shown Bags", columns = GRID_COLUMNS, items = items })
            inner:AddToggle({ label = "Show Free Slots",
                get = function() return MicroBags.Get("slots.backpack.freeSlots") ~= false end,
                set = set("slots.backpack.freeSlots") })
            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--- After a rebuild the page did not ask for (a profile switch while it is
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
