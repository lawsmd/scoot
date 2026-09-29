--------------------------------------------------------------------------------
-- forever/actionbars/editmode.lua
-- The host side of addon.EditMode.RegisterPositionable for the clusters: one
-- registration per container, where its position is stored, how a position
-- is applied around combat, the branded dialog's rows, and the subject: the
-- member whose rows the dialog boxes, picked from that box's header, which
-- is the member dropdown, or by a click on a member's strip (overlays.lua).
-- The engine is core/editmode/positionables.lua and ui/v2/editmode/,
-- shared with Scoot.
--
-- A container is protected by its members' secure buttons, so a restore
-- that lands in combat (a layout switch in a fight) waits for regen; a drop
-- cannot land there, the library refuses the drag. Nothing is stored until
-- the first drag: the container stays on its default anchor, and Reset To
-- Default Position returns it to that anchor's record.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local Clusters = ActionBars.Clusters
local DB = addon.DB

local EditMode = {}
ActionBars.EditMode = EditMode

-- The settings page Configure opens: the Clusters page under the Action
-- Bars group (page.lua). It is the collapsible sections' component id too,
-- so the brand's section key expands that cluster's section.
local NAV_KEY = "actionBarClusters"
EditMode.NAV_KEY = NAV_KEY

--------------------------------------------------------------------------------
-- Store
--------------------------------------------------------------------------------
-- One layout entry per cluster, with a position per Edit Mode layout inside
-- it, beside the cluster's dynamic record:
-- layout[key] = { positions = { [layoutName] = { point, x, y } }, dynamic = {...} }

local store = {
    get = function(key, layoutName)
        local entry = DB.GetLayout(key)
        local positions = entry and entry.positions
        return positions and positions[layoutName] or nil
    end,
    set = function(key, layoutName, point, x, y)
        local entry = DB.GetLayout(key) or {}
        entry.positions = entry.positions or {}
        entry.positions[layoutName] = { point = point, x = x, y = y }
        DB.SetLayout(key, entry)
    end,
}
EditMode.Store = store

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

local idByFrame = setmetatable({}, { __mode = "k" })

local function ApplyPosition(frame, point, x, y, reason)
    local id = idByFrame[frame]
    if InCombatLockdown() then
        addon.Events.RunOutOfCombat(function()
            addon.EditMode.RestorePositionable(frame)
        end, "camelotActionBars.position." .. tostring(id))
        return true
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, x, y)
    -- A restore lands the base position; if Dynamic Layouts holds the
    -- dynamic state, it puts its own position and scale back on top.
    if reason == "restore" and ActionBars.Dynamic then
        ActionBars.Dynamic.Reassert(id)
    end
    return false
end

--------------------------------------------------------------------------------
-- The vocabulary
--------------------------------------------------------------------------------
-- The rows the dialog and the page share. The axis names the member rows:
-- in a vertical cluster a member's lines are rows and its alignment runs
-- left to right; in a horizontal one the lines are columns and the
-- alignment runs top to bottom.

EditMode.AXIS_VALUES = { vertical = "Vertical", horizontal = "Horizontal" }
EditMode.AXIS_ORDER = { "vertical", "horizontal" }
EditMode.ALIGN_ORDER = { "start", "center", "end" }
EditMode.RANGES = {
    spacing = { min = 0, max = 40, step = 1 },
    iconSize = { min = 50, max = 200, step = 5 },
    iconPadding = { min = 2, max = 10, step = 1 },
}

local ALIGN_LABELS = {
    vertical = { start = "Left", center = "Center", ["end"] = "Right" },
    horizontal = { start = "Top", center = "Middle", ["end"] = "Bottom" },
}

--- The member rows' labels for a cluster's axis: the lines row's name and
--- the alignment values.
function EditMode.Labels(vertical)
    return {
        lines = vertical and "Rows" or "Columns",
        align = ALIGN_LABELS[vertical and "vertical" or "horizontal"],
    }
end

--------------------------------------------------------------------------------
-- The subject
--------------------------------------------------------------------------------
-- The member the dialog's member rows edit, held for the session per
-- cluster: the first member until one is picked.

local subjects = {}

--- The subject's index, clamped to the cluster's member count; nil for a
--- cluster with no members or none.
function EditMode.Subject(id)
    local cluster = Clusters.Find(id)
    local n = cluster and cluster.members and #cluster.members or 0
    if n == 0 then return nil end
    return math.max(1, math.min(n, subjects[id] or 1))
end

local function RefreshDialog()
    local Dialog = addon.EditMode and addon.EditMode.Dialog
    if Dialog and Dialog.RefreshMirror then Dialog.RefreshMirror() end
end

--- Pick the subject, from a strip or the box's header. The dialog re-lists
--- around it a frame later: the control that fired this is still in its own
--- handler, and a synchronous rebuild would take it down mid-call.
function EditMode.SetSubject(id, index)
    index = tonumber(index)
    if not index then return end
    subjects[id] = index
    if ActionBars.Overlays then ActionBars.Overlays.Refresh() end
    C_Timer.After(0, RefreshDialog)
end

--- Close the dialog. The library hides it on this event and puts every
--- selection back to highlighted; the case is a selected cluster whose last
--- member was just removed.
function EditMode.CloseDialog()
    if EventRegistry and EventRegistry.TriggerEvent then
        pcall(EventRegistry.TriggerEvent, EventRegistry, "EditModeExternal.hideDialog")
    end
end

--- Remove a member from a strip; when the cluster went with it, the dialog
--- closes.
function EditMode.RemoveMember(id, index)
    local ok = Clusters.RemoveMember(id, index)
    if ok and not Clusters.Find(id) then EditMode.CloseDialog() end
    return ok
end

--------------------------------------------------------------------------------
-- The dialog's rows
--------------------------------------------------------------------------------
-- The provider is called per build and returns the cluster's rows, the
-- subject member's in a box under the member's name, then the buttons. With
-- two or more members the name is the dropdown that picks the subject, so
-- the box says which bar it edits. A label is read at build, so a write
-- that relabels or re-lists the slot (Axis, Buttons, the two buttons)
-- rebuilds it, deferred a frame by the engine; a slider's write lands on
-- release, so a slider may rebuild too. A row whose write would be refused
-- is absent. Remove is the strips' alone, on the owner's call: a strip
-- stands on the bar it removes, where a button in the box acted on
-- whichever member the box showed. End Caps waits for the art.

local function selector(label, values, order, get, set, rebuild)
    return { kind = "selector", label = label, values = values, order = order,
             get = get, set = set, rebuild = rebuild }
end

local function slider(label, range, get, set, rebuild)
    return { kind = "slider", label = label, min = range.min, max = range.max,
             step = range.step or 1, precision = 0, get = get, set = set, rebuild = rebuild }
end

local function button(label, set)
    return { kind = "button", label = label, set = set, rebuild = true }
end

local function clusterField(id, name, default)
    return function()
        local c = Clusters.Find(id)
        local v = c and c[name]
        if v == nil then return default end
        return v
    end
end

local function memberField(id, index, name, default)
    return function()
        local c = Clusters.Find(id)
        local m = c and c.members and c.members[index]
        local v = m and m[name]
        if v == nil then return default end
        return v
    end
end

local function Mirror(id)
    return function()
        local cluster = Clusters.Find(id)
        if not cluster then return {} end
        local vertical = cluster.axis ~= "horizontal"
        local labels = EditMode.Labels(vertical)
        local rows = {}

        rows[#rows + 1] = selector("Axis", EditMode.AXIS_VALUES, EditMode.AXIS_ORDER,
            clusterField(id, "axis", "vertical"),
            function(v) Clusters.SetClusterField(id, "axis", v) end, true)
        rows[#rows + 1] = slider("Spacing", EditMode.RANGES.spacing,
            clusterField(id, "spacing", 4),
            function(v) Clusters.SetClusterField(id, "spacing", v) end)

        local members = cluster.members or {}
        local subject = EditMode.Subject(id)
        local m = subject and members[subject]
        if m then
            if #members > 1 then
                local values, order = {}, {}
                for i, mm in ipairs(members) do
                    local key = tostring(i)
                    values[key] = Clusters.IdentityLabel(mm.identity)
                    order[#order + 1] = key
                end
                rows[#rows + 1] = { kind = "header", values = values, order = order,
                    get = function() return tostring(EditMode.Subject(id)) end,
                    set = function(v) EditMode.SetSubject(id, v) end }
            else
                rows[#rows + 1] = { kind = "header", label = Clusters.IdentityLabel(m.identity) }
            end
            local count = Clusters.ButtonCount(m.identity)
            local function write(name)
                return function(v) Clusters.SetMemberField(id, subject, name, v) end
            end
            rows[#rows + 1] = slider("Buttons", { min = 1, max = count },
                memberField(id, subject, "buttons", count), write("buttons"), true)
            rows[#rows + 1] = slider(labels.lines, { min = 1, max = m.buttons or count },
                memberField(id, subject, "lines", 1), write("lines"))
            rows[#rows + 1] = selector("Alignment", labels.align, EditMode.ALIGN_ORDER,
                memberField(id, subject, "align", "center"), write("align"))
            rows[#rows + 1] = slider("Icon Size", EditMode.RANGES.iconSize,
                memberField(id, subject, "iconSize", 100), write("iconSize"))
            rows[#rows + 1] = slider("Icon Padding", EditMode.RANGES.iconPadding,
                memberField(id, subject, "iconPadding", 2), write("iconPadding"))
            rows[#rows + 1] = { kind = "end" }
        end

        if #Clusters.Placeable() > 0 then
            rows[#rows + 1] = button("Add Bar", function() Clusters.AddMember(id) end)
        end
        if Clusters.FreeActionBar() then
            rows[#rows + 1] = button("Create New Cluster", function() Clusters.NewCluster() end)
        end
        return rows
    end
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

--- Register a container after its first layout. Returns true on the pass
--- that registered it, false when it was registered already or the engine
--- is absent. The default is the cluster's default position, kept by
--- reference: it is what Reset To Default Position returns the frame to.
function EditMode.Register(cluster, container)
    if idByFrame[container] then return false end
    if not (addon.EditMode and addon.EditMode.RegisterPositionable) then return false end
    local id = cluster.id
    idByFrame[container] = id

    local selection = addon.EditMode.RegisterPositionable(container, {
        key = Clusters.Key(id),
        default = Clusters.DefaultPosition(id),
        restoreDefault = false,
        store = store,
        apply = ApplyPosition,
        brand = {
            navKey = NAV_KEY, componentId = NAV_KEY, sectionKey = "cluster" .. id,
            mirror = Mirror(id),
        },
    })

    -- The member strips ride the selection's two states: the library has no
    -- select or deselect callbacks, and these are the methods it calls.
    if selection then
        hooksecurefunc(selection, "ShowSelected", function()
            if ActionBars.Overlays then ActionBars.Overlays.Attach(id) end
        end)
        hooksecurefunc(selection, "ShowHighlighted", function()
            local Overlays = ActionBars.Overlays
            if Overlays and Overlays.IsAttachedTo(id) then Overlays.Detach() end
        end)
    end
    return true
end

--- One line for /camelot actionbars: the stored position for the active
--- layout, or the default.
function EditMode.Describe(id)
    local layoutName = addon.EditMode and addon.EditMode.GetActiveLayoutName
        and addon.EditMode.GetActiveLayoutName() or nil
    local pos = layoutName and store.get(Clusters.Key(id), layoutName) or nil
    if pos and pos.point then
        return string.format("stored %s %.1f %.1f (%s)", pos.point, pos.x or 0, pos.y or 0, layoutName)
    end
    local d = Clusters.DefaultPosition(id)
    return string.format("default %s %.1f %.1f", d.point, d.x, d.y)
end
