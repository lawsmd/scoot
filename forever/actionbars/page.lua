--------------------------------------------------------------------------------
-- forever/actionbars/page.lua
-- The Clusters page: the whole cluster surface in the Camelot menu, under
-- the Action Bars group. Create New Cluster, then one collapsible section per
-- cluster on screen with the dialog's rows, a block per member, Add Bar and
-- Delete Cluster. Every control writes through the edits in clusters.lua,
-- and a write that changes which rows exist re-renders the page. Configure
-- on a cluster's box opens this page with that cluster's section expanded:
-- the section keys are the brand's. The presentation pages of the later
-- phase join the same group. Bar Art, Page Arrows and End Caps wait for
-- the art.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local Clusters = ActionBars.Clusters
local EditMode = ActionBars.EditMode
local SettingsBuilder = addon.UI.SettingsBuilder

local Page = {}
ActionBars.Page = Page

local NAV_KEY = EditMode.NAV_KEY
Page.NAV_KEY = NAV_KEY

local BUTTON_HEIGHT = 26
local BUTTON_GAP = 8

local activeBuilder -- the page's builder while it is drawn
local quiet = false -- a page control is mid-edit

-- Run an edit from a page control. The rebuild inside it asks the page to
-- refresh, which is refused while the page itself is writing; a structural
-- edit, one that adds or removes rows, re-renders after, deferred a frame
-- so the control that fired it finishes its own handler first.
local function edit(builder, fn, structural)
    quiet = true
    local ok, err = pcall(fn)
    quiet = false
    if not ok then error(err, 0) end
    if structural then builder:DeferredRefreshAll() end
end

-- A row of buttons, built by hand since the builder has no button row, and
-- skipped under the search index's scan, which runs every renderer without
-- drawing.
local function AddButtons(builder, parent, specs)
    if SettingsBuilder._scanMode then return end
    local Controls = addon.UI.Controls
    if not (Controls and Controls.CreateButton) then return end
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(BUTTON_HEIGHT)
    local last
    for _, spec in ipairs(specs) do
        local btn = Controls:CreateButton({
            parent = row, text = spec.text, height = BUTTON_HEIGHT, fontSize = 11,
            onClick = spec.onClick,
        })
        if btn then
            if last then
                btn:SetPoint("LEFT", last, "RIGHT", BUTTON_GAP, 0)
            else
                btn:SetPoint("LEFT", row, "LEFT", 0, 0)
            end
            builder:Adopt(btn)
            last = btn
        end
    end
    builder:PlaceCustom(row)
end

--------------------------------------------------------------------------------
-- One member
--------------------------------------------------------------------------------

local function memberBlock(inner, frame, builder, id, index, m, labels)
    local count = Clusters.ButtonCount(m.identity)
    local function field(name, default)
        return function()
            local c = Clusters.Find(id)
            local mm = c and c.members and c.members[index]
            local v = mm and mm[name]
            if v == nil then return default end
            return v
        end
    end
    local function write(name, structural)
        return function(v)
            edit(builder, function() Clusters.SetMemberField(id, index, name, v) end, structural)
        end
    end

    inner:AddLabel(Clusters.IdentityLabel(m.identity))

    local choices = Clusters.Choices(id, index)
    inner:AddSelector({ label = "Identity",
        values = choices.values, order = choices.order,
        disabledOptions = choices.disabledOptions,
        get = field("identity"),
        set = function(v)
            edit(builder, function() Clusters.SetIdentity(id, index, v) end, true)
        end })
    -- The next row's maximum follows this one, so the write re-renders.
    inner:AddSlider({ label = "Buttons", min = 1, max = count, step = 1, precision = 0,
        get = field("buttons", count), set = write("buttons", true) })
    inner:AddSlider({ label = labels.lines, min = 1, max = m.buttons or count, step = 1, precision = 0,
        get = field("lines", 1), set = write("lines") })
    inner:AddSelector({ label = "Alignment", values = labels.align, order = EditMode.ALIGN_ORDER,
        get = field("align", "center"), set = write("align") })
    local size = EditMode.RANGES.iconSize
    inner:AddSlider({ label = "Icon Size", min = size.min, max = size.max, step = size.step, precision = 0,
        minLabel = size.min .. "%", maxLabel = size.max .. "%", displaySuffix = "%",
        get = field("iconSize", 100), set = write("iconSize") })
    local padding = EditMode.RANGES.iconPadding
    inner:AddSlider({ label = "Icon Padding", min = padding.min, max = padding.max, step = padding.step,
        precision = 0, get = field("iconPadding", 2), set = write("iconPadding") })
    inner:AddToggle({ label = "Always Show Buttons",
        get = function() return field("alwaysShowButtons", true)() and true or false end,
        set = write("alwaysShowButtons") })
    if Clusters.CanRemove(id, index) then
        AddButtons(inner, frame, {
            { text = "Remove", onClick = function()
                edit(builder, function() Clusters.RemoveMember(id, index) end, true)
            end },
        })
    end
end

--------------------------------------------------------------------------------
-- One cluster
--------------------------------------------------------------------------------

local function clusterSection(builder, cluster)
    local id = cluster.id
    builder:AddCollapsibleSection({
        title = Clusters.Label(cluster), componentId = NAV_KEY, sectionKey = "cluster" .. id,
        defaultExpanded = true,
        buildContent = function(frame, inner)
            local c = Clusters.Find(id)
            if not c then
                inner:Finalize()
                return
            end
            local vertical = c.axis ~= "horizontal"
            local labels = EditMode.Labels(vertical)

            -- The member rows are labelled by the axis, so the write re-renders.
            inner:AddSelector({ label = "Axis", values = EditMode.AXIS_VALUES, order = EditMode.AXIS_ORDER,
                get = function()
                    local cc = Clusters.Find(id)
                    return cc and cc.axis or "vertical"
                end,
                set = function(v)
                    edit(builder, function() Clusters.SetClusterField(id, "axis", v) end, true)
                end })
            local spacing = EditMode.RANGES.spacing
            inner:AddSlider({ label = "Spacing", min = spacing.min, max = spacing.max, step = spacing.step,
                precision = 0,
                get = function()
                    local cc = Clusters.Find(id)
                    return cc and cc.spacing or 4
                end,
                set = function(v)
                    edit(builder, function() Clusters.SetClusterField(id, "spacing", v) end)
                end })

            for index, m in ipairs(c.members or {}) do
                memberBlock(inner, frame, builder, id, index, m, labels)
            end

            local buttons = {}
            if #Clusters.Placeable() > 0 then
                buttons[#buttons + 1] = { text = "Add Bar", onClick = function()
                    edit(builder, function() Clusters.AddMember(id) end, true)
                end }
            end
            if Clusters.CanDelete(id) then
                buttons[#buttons + 1] = { text = "Delete Cluster", onClick = function()
                    local label = Clusters.Label(Clusters.Find(id) or cluster)
                    addon.Dialogs:Confirm("Delete " .. label .. "?", function()
                        edit(builder, function() Clusters.DeleteCluster(id) end, true)
                    end)
                end }
            end
            if #buttons > 0 then
                AddButtons(inner, frame, buttons)
            end
            inner:Finalize()
        end,
    })
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

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

    if Clusters.FreeActionBar() then
        AddButtons(builder, scrollContent, {
            { text = "Create New Cluster", onClick = function()
                edit(builder, function() Clusters.NewCluster() end, true)
            end },
        })
    end

    for _, cluster in ipairs(Clusters.Get()) do
        if Clusters.OnScreen(cluster) then
            clusterSection(builder, cluster)
        end
    end

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
