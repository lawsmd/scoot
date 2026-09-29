--------------------------------------------------------------------------------
-- forever/actionbars/clusters.lua
-- The clusters: one or more bars stacked along one axis with a gap, the unit
-- the action bars are positioned, driven and edited in. Each member holds
-- one identity from the pool in bars.lua, and the identity's frame is
-- adopted into the cluster's container; an identity no cluster holds is
-- parked. The document is the stored cluster list, or the defaults below
-- until the first edit copies them into the profile. Every edit writes the
-- document and lays every cluster out again. The positionable (editmode.lua)
-- and the Dynamic Layouts adapter (dynamic.lua) register on a container
-- after its first layout; every later layout restores the stored position
-- and puts a held dynamic state back on top.
--
-- Every write here is a SetParent or a SetPoint on a frame with secure
-- children, so a pass runs out of combat, and one asked for in a fight is
-- queued once for regen.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local Clusters = {}
ActionBars.Clusters = Clusters

local DB = addon.DB

local DOCUMENT = "actionBars.clusters"
local NEXT_ID = "actionBars.nextClusterId"
local REBUILD_KEY = "camelotActionBars.clusters"

-- Above the dimmed main bar (frame level 50) and its buttons.
local CONTAINER_LEVEL = 60

-- Buttons per identity kind; the pool in bars.lua loads after this file.
local BUTTON_COUNT = { action = 12, pet = 10, stance = 10 }

--------------------------------------------------------------------------------
-- The default document
--------------------------------------------------------------------------------

local function member(identity, extra)
    local m = {
        identity = identity, buttons = 12, lines = 1, align = "center",
        iconSize = 100, iconPadding = 2, alwaysShowButtons = true, barArt = false,
    }
    if extra then
        for k, v in pairs(extra) do m[k] = v end
    end
    return m
end

-- The spacer is Forever's own BOTTOM_ACTION_BARS_SPACER_Y, from the client's
-- Camelot preset constants.
local SPACING = 4

Clusters.DEFAULTS = {
    { id = 1, axis = "vertical", spacing = SPACING, endCaps = true,
      members = {
          member("bar1", { barArt = true, pageArrows = true }),
          member("bar2"), member("bar3"), member("bar4"),
      } },
    { id = 2, axis = "vertical", spacing = SPACING, endCaps = false,
      members = { member("pet", { buttons = 10 }) } },
    { id = 3, axis = "vertical", spacing = SPACING, endCaps = false,
      members = { member("stance", { buttons = 10 }) } },
    { id = 4, axis = "horizontal", spacing = SPACING, endCaps = false,
      members = { { identity = "microMenu", align = "center" } } },
    { id = 5, axis = "horizontal", spacing = SPACING, endCaps = false,
      members = { { identity = "bags", align = "center" } } },
}

-- Where each default cluster stands until Edit Mode stores a position. The
-- main cluster is centered at the bottom of the screen with its bottom
-- member 55 units up: the owner's call after the first look, the bars
-- being the one place Camelot departs from the stock arrangement on
-- purpose. The pet and stance clusters take Blizzard's bottom stacking rule
-- when they are built; the two leased clusters keep Forever's own anchors
-- for the micro menu and the bags until their lease is built and new
-- defaults are found. A cluster with no row here, a new one, stands at the
-- screen center.
Clusters.DEFAULT_ANCHOR = {
    [1] = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 0, y = 55 },
    [4] = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 116.5, y = 6 },
    [5] = { point = "BOTTOMLEFT", relativeTo = "MicroMenuContainer", relativePoint = "BOTTOMRIGHT", x = 7, y = -4 },
}

--- The layout key a cluster's Edit Mode positions and its dynamic record
--- sit under.
function Clusters.Key(id)
    return "actionBarCluster." .. tostring(id)
end

--- The stored document, or the defaults when the player has never edited a
--- cluster. Nothing is written here.
function Clusters.Get()
    local doc = DB.GetDocument(DOCUMENT)
    if type(doc) == "table" then return doc end
    return Clusters.DEFAULTS
end

--- The cluster with this id, or nil.
function Clusters.Find(id)
    for _, cluster in ipairs(Clusters.Get()) do
        if cluster.id == id then return cluster end
    end
    return nil
end

-- Cluster 1 holds the bars a fresh profile starts with. It cannot be
-- deleted and always keeps at least one action bar: the feature's own
-- switch is the way to have no Camelot bars at all.
local PRIMARY = 1
Clusters.PRIMARY = PRIMARY

local function isAction(token)
    local row = ActionBars.POOL and ActionBars.POOL[token]
    return row ~= nil and row.kind == "action"
end

local function hasAction(cluster)
    for _, m in ipairs(cluster.members or {}) do
        if isAction(m.identity) then return true end
    end
    return false
end

-- How many action bars the cluster holds besides the member at `index`.
local function actionsBesides(cluster, index)
    local n = 0
    for i, m in ipairs(cluster.members or {}) do
        if i ~= index and isAction(m.identity) then n = n + 1 end
    end
    return n
end

--- The label Edit Mode and the window show. A cluster holding an action bar
--- is "Action Bar Cluster n", n its place among those clusters in document
--- order, so cluster 1 is always the first; a cluster of other kinds is
--- named by its members, "Pet Bar".
function Clusters.Label(cluster)
    if hasAction(cluster) then
        local n = 0
        for _, c in ipairs(Clusters.Get()) do
            if hasAction(c) then
                n = n + 1
                if c.id == cluster.id then break end
            end
        end
        return "Action Bar Cluster " .. n
    end
    local pool = ActionBars.POOL or {}
    local labels = {}
    for _, m in ipairs(cluster.members or {}) do
        local row = pool[m.identity]
        labels[#labels + 1] = row and row.label or tostring(m.identity)
    end
    return table.concat(labels, ", ")
end

--- The id of the cluster holding an identity, or nil when it is unassigned.
function Clusters.Owner(token)
    for _, cluster in ipairs(Clusters.Get()) do
        for _, m in ipairs(cluster.members or {}) do
            if m.identity == token then return cluster.id end
        end
    end
    return nil
end

--- The identities no cluster holds, in pool order.
function Clusters.Unassigned()
    local out = {}
    for _, token in ipairs(ActionBars.POOL_ORDER or {}) do
        if not Clusters.Owner(token) then out[#out + 1] = token end
    end
    return out
end

--------------------------------------------------------------------------------
-- Edits
--------------------------------------------------------------------------------
-- Each edit writes the document and lays every cluster out again. The first
-- edit copies the defaults into the profile; until then the document is
-- absent and the defaults are read in place. Ids come from the settings
-- path and are never reused.

local function copy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = type(v) == "table" and copy(v) or v
    end
    return out
end

local function Editable()
    local doc = DB.GetDocument(DOCUMENT)
    if type(doc) ~= "table" then
        doc = copy(Clusters.DEFAULTS)
        DB.SetDocument(DOCUMENT, doc)
    end
    return doc
end

local function find(doc, id)
    for i, cluster in ipairs(doc) do
        if cluster.id == id then return cluster, i end
    end
    return nil
end

local function memberCount(token)
    local row = ActionBars.POOL and ActionBars.POOL[token]
    return row and BUTTON_COUNT[row.kind] or 12
end

--- Buttons an identity's bar holds.
function Clusters.ButtonCount(token)
    return memberCount(token)
end

--- The name the dropdowns and the page show for an identity.
function Clusters.IdentityLabel(token)
    local row = ActionBars.POOL and ActionBars.POOL[token]
    return row and row.label or tostring(token)
end

-- Whether an identity's frame exists: the eight action bars are built, and
-- pet, stance and the leased kinds come with their phases. Until then a
-- member of those kinds is skipped by the layout, its cluster has no
-- container, and the surfaces list neither.
local function isBuilt(token)
    local frames = ActionBars.Frames
    return frames ~= nil and frames[token] ~= nil
end

--- Whether the cluster has a container to show: a member whose frame is
--- built. The page lists these clusters.
function Clusters.OnScreen(cluster)
    for _, m in ipairs(cluster.members or {}) do
        if isBuilt(m.identity) then return true end
    end
    return false
end

--- The identities a new member can take: unassigned, with a built frame, in
--- pool order. Add Bar reads this and is absent when it is empty.
function Clusters.Placeable()
    local out = {}
    for _, token in ipairs(Clusters.Unassigned()) do
        if isBuilt(token) then out[#out + 1] = token end
    end
    return out
end

--- The lowest-numbered action bar no cluster holds, with its frame built,
--- or nil when every action bar is placed: what a new cluster starts with,
--- the owner's call, so Create New Cluster is absent without one.
function Clusters.FreeActionBar()
    for _, token in ipairs(Clusters.Placeable()) do
        if isAction(token) then return token end
    end
    return nil
end

--- One member's identity dropdown: every built identity in pool order, the
--- member's own plain, one another member holds (in any cluster) disabled,
--- and for cluster 1's last action bar every other kind disabled. A greyed
--- entry carries no icon or tooltip: the greying says enough, the owner's
--- call. The shape is the selector control's.
function Clusters.Choices(id, index)
    local cluster = Clusters.Find(id)
    local m = cluster and cluster.members and cluster.members[index]
    local own = m and m.identity
    local lastAction = cluster ~= nil and id == PRIMARY and actionsBesides(cluster, index) == 0
    local values, order, disabled = {}, {}, {}
    for _, token in ipairs(ActionBars.POOL_ORDER or {}) do
        if isBuilt(token) or token == own then
            values[token] = Clusters.IdentityLabel(token)
            order[#order + 1] = token
            local held = token ~= own and Clusters.Owner(token) ~= nil
            if held or (lastAction and not isAction(token)) then
                disabled[token] = true
            end
        end
    end
    return { values = values, order = order, disabledOptions = disabled }
end

--- Whether Remove is offered for a member: every member but the last action
--- bar of cluster 1.
function Clusters.CanRemove(id, index)
    local cluster = Clusters.Find(id)
    if not (cluster and cluster.members and cluster.members[index]) then return false end
    return not (id == PRIMARY and actionsBesides(cluster, index) == 0)
end

--- Whether Delete Cluster is offered: every cluster but 1.
function Clusters.CanDelete(id)
    return id ~= PRIMARY and Clusters.Find(id) ~= nil
end

local function clamp(v, lo, hi)
    v = tonumber(v)
    if not v then return nil end
    return math.max(lo, math.min(hi, math.floor(v + 0.5)))
end

local function flag(v)
    return v and true or false
end

local AXES = { vertical = true, horizontal = true }
local ALIGNS = { start = true, center = true, ["end"] = true }

-- field -> the value the write takes, or nil to refuse it
local CLUSTER_FIELDS = {
    axis = function(v) return AXES[v] and v or nil end,
    spacing = function(v) return clamp(v, 0, 40) end,
    endCaps = flag,
}

local MEMBER_FIELDS = {
    buttons = function(v, m) return clamp(v, 1, memberCount(m.identity)) end,
    lines = function(v, m) return clamp(v, 1, m.buttons or memberCount(m.identity)) end,
    align = function(v) return ALIGNS[v] and v or nil end,
    iconSize = function(v) return clamp(v, 50, 200) end,
    iconPadding = function(v) return clamp(v, 2, 10) end,
    alwaysShowButtons = flag,
    barArt = flag,
    pageArrows = flag,
}

local function commit(doc)
    DB.SetDocument(DOCUMENT, doc)
    Clusters.Rebuild()
    return true
end

--- Write one of axis, spacing and endCaps.
function Clusters.SetClusterField(id, field, value)
    local accept = CLUSTER_FIELDS[field]
    if not accept then return false end
    local v = accept(value)
    if v == nil then return false end
    local doc = Editable()
    local cluster = find(doc, id)
    if not cluster then return false end
    cluster[field] = v
    return commit(doc)
end

--- Write one member field by the member's index in the cluster.
function Clusters.SetMemberField(id, index, field, value)
    local accept = MEMBER_FIELDS[field]
    if not accept then return false end
    local doc = Editable()
    local cluster = find(doc, id)
    local m = cluster and cluster.members and cluster.members[index]
    if not m then return false end
    local v = accept(value, m)
    if v == nil then return false end
    m[field] = v
    if field == "buttons" and (m.lines or 1) > v then m.lines = v end
    return commit(doc)
end

--- Give a member another identity. Refused for an identity another member
--- holds (set that member to something free first), and for a change that
--- would leave cluster 1 without an action bar.
function Clusters.SetIdentity(id, index, token)
    if not (ActionBars.POOL and ActionBars.POOL[token]) then return false end
    local doc = Editable()
    local cluster = find(doc, id)
    local m = cluster and cluster.members and cluster.members[index]
    if not m then return false end
    if m.identity == token then return true end
    if Clusters.Owner(token) then return false end
    if id == PRIMARY and not isAction(token) and actionsBesides(cluster, index) == 0 then
        return false
    end
    m.identity = token
    local count = memberCount(token)
    m.buttons = math.min(m.buttons or count, count)
    m.lines = math.min(m.lines or 1, m.buttons)
    return commit(doc)
end

--- Add a member holding the identity, or the first placeable one. Refused
--- when every identity is placed.
function Clusters.AddMember(id, token)
    token = token or Clusters.Placeable()[1]
    if not token or Clusters.Owner(token) then return false end
    local doc = Editable()
    local cluster = find(doc, id)
    if not cluster then return false end
    cluster.members = cluster.members or {}
    cluster.members[#cluster.members + 1] = member(token, { buttons = memberCount(token) })
    return commit(doc)
end

--- Remove a member; removing the last one removes the cluster. Refused for
--- the last action bar of cluster 1.
function Clusters.RemoveMember(id, index)
    local doc = Editable()
    local cluster, at = find(doc, id)
    if not (cluster and cluster.members and cluster.members[index]) then return false end
    if id == PRIMARY and actionsBesides(cluster, index) == 0 then return false end
    table.remove(cluster.members, index)
    if #cluster.members == 0 then
        table.remove(doc, at)
        DB.SetLayout(Clusters.Key(id), nil)
    end
    return commit(doc)
end

--- A one-member cluster at the screen center, holding the identity or the
--- lowest free action bar. Returns the new id, or nil when there is none.
function Clusters.NewCluster(token)
    token = token or Clusters.FreeActionBar()
    if not token or Clusters.Owner(token) then return nil end
    local doc = Editable()
    local id = tonumber(DB.Get(NEXT_ID)) or 6
    DB.Set(NEXT_ID, id + 1)
    doc[#doc + 1] = {
        id = id, axis = "vertical", spacing = SPACING, endCaps = false,
        members = { member(token, { buttons = memberCount(token) }) },
    }
    commit(doc)
    return id
end

--- Remove a cluster and its layout entry; its members are parked. Cluster 1
--- is refused.
function Clusters.DeleteCluster(id)
    if id == PRIMARY then return false end
    local doc = Editable()
    local _, at = find(doc, id)
    if not at then return false end
    table.remove(doc, at)
    DB.SetLayout(Clusters.Key(id), nil)
    return commit(doc)
end

--------------------------------------------------------------------------------
-- The members
--------------------------------------------------------------------------------

-- The grid bit Edit Mode's Always Show Buttons handler sets on Blizzard's
-- buttons. A button's SetShowGrid writes its showgrid attribute only from
-- secure code, and a call from this file is not, so the bit is written here
-- and the bar's own SetShowGrid then runs its strata and shown-buttons
-- passes over it. Out of combat only: the caller queues the build.
local function SetGridBit(bar, show)
    local reason = ACTION_BUTTON_SHOW_GRID_REASON_CVAR
    for _, button in ipairs(bar.actionButtons) do
        local current = button:GetAttribute("showgrid") or 0
        local wanted = show and bit.bor(current, reason) or bit.band(current, bit.bnot(reason))
        if wanted ~= current then
            button:SetAttribute("showgrid", wanted)
        end
    end
end

-- The member's fields, written through the same fields Blizzard's Edit Mode
-- handlers write on its own bars (Blizzard_EditMode/Shared/
-- EditModeSystemTemplates.lua): the axis decides the orientation, the icon
-- size scales the button containers, and the grid is rebuilt after.
local function ApplyMember(bar, m, vertical)
    bar.isHorizontal = vertical
    bar.addButtonsToRight = true
    bar.addButtonsToTop = vertical
    bar.numRows = m.lines or 1
    bar.numButtonsShowable = math.min(m.buttons or bar.numButtons, bar.numButtons)
    bar.buttonPadding = m.iconPadding or 2

    local scale = (m.iconSize or 100) / 100
    for _, button in ipairs(bar.actionButtons) do
        button.container:SetScale(scale)
    end

    local showGrid = m.alwaysShowButtons ~= false
    SetGridBit(bar, showGrid)
    bar:SetShowGrid(showGrid, ACTION_BUTTON_SHOW_GRID_REASON_CVAR)
    -- The grid cache reads clean after the load-time pass, and the container
    -- scale is not in it, so the grid is forced and its own Layout follows.
    bar.oldGridSettings = nil
    bar:UpdateGridLayout()
    bar:Layout()
end

-- An identity no cluster holds draws nowhere.
local function Park(frame)
    local parked = CamelotActionBarsParked
    if not parked or frame:GetParent() == parked then return end
    frame:SetParent(parked)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", parked, "CENTER", 0, 0)
end

--------------------------------------------------------------------------------
-- The containers
--------------------------------------------------------------------------------

local containers = {}
local report = {}
local defaults = {}
local captured = {}

local function Container(id)
    local container = containers[id]
    if not container then
        container = CreateFrame("Frame", "CamelotActionBarCluster" .. id, UIParent)
        addon.Strata.ApplyHUD(container, CONTAINER_LEVEL)
        containers[id] = container
    end
    return container
end

local function Anchor(container, id)
    local a = Clusters.DEFAULT_ANCHOR[id]
    container:ClearAllPoints()
    if not a then
        container:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return "CENTER UIParent"
    end
    local relativeTo = _G[a.relativeTo] or UIParent
    container:SetPoint(a.point, relativeTo, a.relativePoint, a.x, a.y)
    return string.format("%s %s %s %.1f %.1f", a.point, a.relativeTo, a.relativePoint, a.x, a.y)
end

--- The container's default position as an anchor on UIParent, in the
--- container's base scale. A plain UIParent anchor in DEFAULT_ANCHOR is the
--- record itself; a relative anchor, and a cluster with no row, is captured
--- off the container's rect at every layout while it stands on its anchor.
--- Kept by reference: LibEditMode holds it for Reset To Default Position and
--- the adapter reads it as the base position.
function Clusters.DefaultPosition(id)
    local d = defaults[id]
    if not d then
        local a = Clusters.DEFAULT_ANCHOR[id]
        if a and a.relativeTo == "UIParent" and a.relativePoint == a.point then
            d = { point = a.point, x = a.x, y = a.y }
        else
            d = { point = "BOTTOMLEFT", x = 0, y = 0 }
            captured[id] = true
        end
        defaults[id] = d
    end
    return d
end

-- GetLeft and GetBottom answer in the container's own scale; the base
-- position is the pair at scale 1.
local function CaptureDefault(container, id)
    local d = Clusters.DefaultPosition(id)
    if not captured[id] then return end
    local left, bottom, scale = container:GetLeft(), container:GetBottom(), container:GetScale()
    if left and bottom and scale and scale > 0 then
        d.x, d.y = left * scale, bottom * scale
    end
end

-- After the layout: the label the selection reads lazily, the positionable
-- and the adapter on the container's first pass, the stored position on
-- every later one, and the adapter's snap last so a held dynamic state
-- lands on top.
local function Place(cluster, container, rows)
    rows.label = Clusters.Label(cluster)
    container.editModeName = rows.label
    local EditMode, Dynamic = ActionBars.EditMode, ActionBars.Dynamic
    local fresh = EditMode and EditMode.Register(cluster, container)
    if not fresh and addon.EditMode and addon.EditMode.RestorePositionable then
        addon.EditMode.RestorePositionable(container)
    end
    if Dynamic then Dynamic.Register(cluster, container) end
    rows.position = EditMode and EditMode.Describe(cluster.id) or "no positionable"
    rows.dynamic = Dynamic and Dynamic.Describe(cluster.id) or nil
end

--- Lay one cluster out: anchor the container, adopt the members whose frames
--- exist and lay each out, size the container by their extents, then anchor
--- each member in its slot by its alignment.
local function LayoutCluster(cluster)
    local pool = ActionBars.POOL or {}
    local frames = ActionBars.Frames or {}
    local vertical = cluster.axis ~= "horizontal"
    local spacing = cluster.spacing or SPACING
    local rows = { id = cluster.id, axis = cluster.axis, members = {} }
    report[#report + 1] = rows

    local built = {}
    for _, m in ipairs(cluster.members or {}) do
        local row = pool[m.identity]
        local bar = row and row.kind == "action" and frames[m.identity] or nil
        if bar then
            built[#built + 1] = { bar = bar, m = m }
        else
            rows.members[#rows.members + 1] = string.format("%s skipped (%s)", tostring(m.identity),
                row and row.kind or "unknown identity")
        end
    end
    if #built == 0 then
        rows.note = "no container: no action member"
        rows.label = Clusters.Label(cluster)
        local container = containers[cluster.id]
        if container then container:Hide() end
        return
    end

    -- The container first, anchored, with a size to be replaced: a bar sizes
    -- itself from its button containers' rects, and those resolve only under
    -- an anchored ancestor, so every member is adopted and pointed before it
    -- is laid out and measured.
    local container = Container(cluster.id)
    container:Show()
    container:SetSize(1, 1)
    rows.anchor = Anchor(container, cluster.id)

    local along, across = 0, 0
    for _, e in ipairs(built) do
        e.bar:SetParent(container)
        e.bar:ClearAllPoints()
        e.bar:SetPoint("CENTER", container, "CENTER", 0, 0)
        ApplyMember(e.bar, e.m, vertical)
        e.w, e.h = e.bar:GetWidth(), e.bar:GetHeight()
        rows.members[#rows.members + 1] = string.format("%s built %.0fx%.0f", e.m.identity, e.w, e.h)
        if vertical then
            along = along + e.h
            across = math.max(across, e.w)
        else
            along = along + e.w
            across = math.max(across, e.h)
        end
    end
    along = along + spacing * (#built - 1)

    if vertical then
        container:SetSize(across, along)
    else
        container:SetSize(along, across)
    end

    local offset = 0
    for _, e in ipairs(built) do
        local align = e.m.align or "center"
        e.bar:SetParent(container)
        e.bar:ClearAllPoints()
        if vertical then
            local point = (align == "start" and "TOPLEFT") or (align == "end" and "TOPRIGHT") or "TOP"
            e.bar:SetPoint(point, container, point, 0, -offset)
            offset = offset + e.h + spacing
        else
            local point = (align == "start" and "TOPLEFT") or (align == "end" and "BOTTOMLEFT") or "LEFT"
            e.bar:SetPoint(point, container, point, offset, 0)
            offset = offset + e.w + spacing
        end
    end

    rows.size = string.format("%.0fx%.0f", container:GetWidth(), container:GetHeight())
    CaptureDefault(container, cluster.id)
    Place(cluster, container, rows)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local built = false

--- Every cluster in the document, out of combat; a pass asked for in a
--- fight is queued once for regen. Identities no cluster holds are parked
--- and the containers of clusters no longer in the document are hidden
--- before the layouts run.
function Clusters.Rebuild()
    if InCombatLockdown() then
        addon.Events.RunOutOfCombat(Clusters.Rebuild, REBUILD_KEY)
        return
    end
    wipe(report)
    local doc = Clusters.Get()
    local assigned, live = {}, {}
    for _, cluster in ipairs(doc) do
        live[cluster.id] = true
        for _, m in ipairs(cluster.members or {}) do
            assigned[m.identity] = true
        end
    end
    for token, frame in pairs(ActionBars.Frames or {}) do
        if not assigned[token] then Park(frame) end
    end
    for id, container in pairs(containers) do
        if not live[id] then container:Hide() end
    end
    for _, cluster in ipairs(doc) do
        LayoutCluster(cluster)
    end
    built = true
    -- The surfaces that draw the document re-lay over the new layout.
    if ActionBars.Overlays then ActionBars.Overlays.Refresh() end
    if ActionBars.Page then ActionBars.Page.Refresh() end
end

--- The first pass, from the bars' build. The caller runs out of combat.
function Clusters.Build()
    if built then return end
    Clusters.Rebuild()
end

function Clusters.IsBuilt()
    return built
end

function Clusters.Container(id)
    return containers[id]
end

--- The rows /camelot actionbars prints.
function Clusters.Report()
    return report
end

-- After a profile switch the clusters come from the new profile's document.
-- The positionable's own layout callback restores each position, and the
-- pass here restores it again after the layout. The initial pass has no
-- frames yet, and a resync pass keeps the profile it had.
addon.Profiles.RegisterApplyStep("camelotActionBars", function(_, ctx)
    if ctx.initial or ctx.resync or not built then return end
    Clusters.Rebuild()
end, 30)
