--------------------------------------------------------------------------------
-- forever/objectivetracker/currentpage.lua
-- The Current Objectives settings page: the pane's behaviour, then the four
-- look sections the tracker page draws, over the pane's own keys
-- (objectiveTracker.current.*). Loads on retail too, like page.lua.
--------------------------------------------------------------------------------

local addonName, addon = ...

local OT = addon.ObjectiveTracker
local Style = OT.Style
local Page = OT.Page
local DB = addon.DB
local SettingsBuilder = addon.UI.SettingsBuilder

local NAV_KEY = "currentObjectives"
local PANE = Style.CURRENT

local function apply()
    Style.Apply()
end

local function addToggle(inner, label, description, key)
    inner:AddToggle({ label = label, description = description,
        get = function() return Style.Get("current", key) and true or false end,
        set = function(v)
            DB.Set(Style.Path("current", key), v and true or false)
            apply()
        end })
end

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    builder:AddCollapsibleSection({ title = "Behaviour", componentId = NAV_KEY,
        sectionKey = "behaviour", defaultExpanded = true,
        buildContent = function(_, inner)
            addToggle(inner, "Enable",
                "Draw a second pane that takes a tracked quest out of the tracker while it is the one you are working on. Off, every quest stays in the tracker.",
                "enabled")
            addToggle(inner, "Mark Current On Entering Area",
                "A quest moves to the pane while you stand inside the area the map marks for it, and returns when you leave.",
                "onEnterArea")
            addToggle(inner, "Mark Current On Progress",
                "A quest moves to the pane when one of its objectives advances, and stays for the hold below.",
                "onProgress")
            inner:AddSlider({ label = "Hold",
                description = "How long a quest stays in the pane after progress on it, in seconds. Another advance restarts the hold.",
                min = Style.HOLD.min, max = Style.HOLD.max, step = Style.HOLD.step,
                minLabel = Style.HOLD.min .. "s", maxLabel = Style.HOLD.max .. "s",
                precision = 0, displaySuffix = "s",
                get = function() return Style.HoldSeconds() end,
                set = function(v)
                    DB.Set(Style.Path("current", "holdSeconds"), tonumber(v) or Style.HOLD.default)
                    apply()
                end })
            inner:Finalize()
        end })

    Page.AddLookSections(builder, PANE, NAV_KEY, "pane")

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, function(panel, scrollContent)
    Render(panel, scrollContent)
end)
