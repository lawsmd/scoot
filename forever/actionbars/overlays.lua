--------------------------------------------------------------------------------
-- forever/actionbars/overlays.lua
-- The member strips: while a cluster is selected in Edit Mode, each member
-- wears a strip on its bar with the identity dropdown and Remove, and a
-- click on a strip makes that member the dialog's subject (editmode.lua).
-- The strips ride the selection's two states through the hooks editmode.lua
-- puts on ShowSelected and ShowHighlighted, since the library has no select
-- or deselect callbacks; Edit Mode exit and combat take them down. One
-- cluster is selected at a time, so one layer of pooled strips serves them
-- all, re-laid from the document after every rebuild and every subject
-- change.
--
-- The layer stands on the DIALOG strata under the library's dialog and
-- above the selection box. Only the strips take the mouse, so the rest of
-- the box keeps the library's drag. The strips persist hidden between
-- selections.
--
-- A strip draws no box of its own: the two controls carry the skin's
-- bodies, each with its border, and a box around them read as a frame
-- around frames on the owner's second look. The subject's strip is the one
-- at full opacity; the others sit at three quarters.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local Clusters = ActionBars.Clusters
local EditMode = ActionBars.EditMode
local OWNER = ActionBars.OWNER

local Overlays = {}
ActionBars.Overlays = Overlays

local STRIP_HEIGHT = 26
local PAD = 6
local GAP = 6
-- The dropdown control's whole width: the skin stands a stepper each side
-- of the field, and the field between them takes what is left.
local DROPDOWN_WIDTH = 210
local REMOVE_WIDTH = 64
local CONTROL_HEIGHT = 22
-- Three quarters for the strips that are not the subject, so they sit in
-- the selection box rather than on it; the subject's draws at full.
local STRIP_ALPHA = 0.75
-- Above the selection box, under the library's dialog at 200.
local LAYER_LEVEL = 110

local layer
local strips
local attached -- the selected cluster's id while the strips are up

--------------------------------------------------------------------------------
-- A strip
--------------------------------------------------------------------------------

-- The subject's strip stands at full opacity; the others at STRIP_ALPHA.
local function Mark(strip, on)
    strip:SetAlpha(on and 1 or STRIP_ALPHA)
end

local function CreateStrip()
    local Controls = addon.UI.Controls
    local strip = CreateFrame("Frame", nil, layer)
    strip:SetHeight(STRIP_HEIGHT)
    strip:EnableMouse(true)
    strip:SetAlpha(STRIP_ALPHA)

    strip._dropdown = Controls:CreateDropdown({
        parent = strip, width = DROPDOWN_WIDTH, height = CONTROL_HEIGHT,
        values = {}, order = {},
        get = function() return strip._identity end,
        set = function(token)
            if not attached or not strip._index then return end
            EditMode.SetSubject(attached, strip._index)
            Clusters.SetIdentity(attached, strip._index, token)
        end,
    })
    strip._dropdown:SetPoint("LEFT", strip, "LEFT", PAD, 0)

    strip._remove = Controls:CreateButton({
        parent = strip, text = "Remove", width = REMOVE_WIDTH, height = CONTROL_HEIGHT, fontSize = 11,
        onClick = function()
            if not attached or not strip._index then return end
            EditMode.SetSubject(attached, strip._index)
            EditMode.RemoveMember(attached, strip._index)
        end,
    })
    strip._remove:SetPoint("LEFT", strip._dropdown, "RIGHT", GAP, 0)

    strip:SetScript("OnMouseDown", function()
        if attached and strip._index then EditMode.SetSubject(attached, strip._index) end
    end)
    strip:Hide()
    return strip
end

-- Lay one strip on a member's bar from the document.
local function LayStrip(strip, id, index, m, bar, subject)
    strip._index = index
    strip._identity = m.identity
    local choices = Clusters.Choices(id, index)
    strip._dropdown:SetOptions(choices.values, choices.order, choices.disabledOptions)
    strip._dropdown:SetValue(m.identity)

    local removable = Clusters.CanRemove(id, index)
    strip._remove:SetShown(removable)
    local width = PAD + DROPDOWN_WIDTH + PAD
    if removable then width = width + GAP + REMOVE_WIDTH end
    strip:SetWidth(width)
    Mark(strip, index == subject)

    strip:ClearAllPoints()
    strip:SetPoint("CENTER", bar, "CENTER", 0, 0)
    strip:Show()
end

--------------------------------------------------------------------------------
-- The layer
--------------------------------------------------------------------------------

local function EnsureLayer()
    if layer then return end
    layer = CreateFrame("Frame", "CamelotActionBarOverlays", UIParent)
    layer:SetFrameStrata("DIALOG")
    layer:SetFrameLevel(LAYER_LEVEL)
    layer:SetAllPoints(UIParent)
    layer:EnableMouse(false)
    layer:Hide()
    strips = addon.Pool.NewIndexed(CreateStrip)
    -- No editing surface stays up in combat.
    addon.Events.On(OWNER .. ".overlays", "PLAYER_REGEN_DISABLED", function()
        Overlays.Detach()
    end)
end

--- Whether the strips are up on this cluster.
function Overlays.IsAttachedTo(id)
    return attached ~= nil and attached == id
end

--- Put the strips on a cluster: from the ShowSelected hook. Refused in
--- combat, in the dynamic view (whose dialog is not the cluster's), and
--- outside Edit Mode.
function Overlays.Attach(id)
    if InCombatLockdown() then return end
    local EM = addon.EditMode
    if not (EM and EM.IsEditing and EM.IsEditing()) then return end
    if EM.IsDynamicView and EM.IsDynamicView() then return end
    EnsureLayer()
    attached = id
    Overlays.Refresh()
end

--- Take the strips down.
function Overlays.Detach()
    if not attached then return end
    attached = nil
    if strips then strips:HideFrom(1) end
    if layer then layer:Hide() end
end

--- Re-lay the strips of the attached cluster from the document: after every
--- rebuild and every subject change. A cluster gone from the document, or
--- one whose container is hidden, takes the strips down.
function Overlays.Refresh()
    if not attached then return end
    local id = attached
    local cluster = Clusters.Find(id)
    local container = Clusters.Container(id)
    if not (cluster and container and container:IsShown()) then
        Overlays.Detach()
        return
    end
    local subject = EditMode.Subject(id)
    local frames = ActionBars.Frames or {}
    local n = 0
    for index, m in ipairs(cluster.members or {}) do
        local bar = frames[m.identity]
        if bar and bar:GetParent() == container then
            n = n + 1
            LayStrip(strips:Get(n), id, index, m, bar, subject)
        end
    end
    strips:HideFrom(n + 1)
    layer:SetShown(n > 0)
end
