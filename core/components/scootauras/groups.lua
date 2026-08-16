-- scootauras/groups.lua - Group frames: pool, membership reconcile, layout
--
-- A group is a Scoot-owned, LibEditMode-registered frame that anchors member
-- visuals in a row or column. Members keep their own containers, units, and
-- styling; the group owns layout only. Group frames are session-permanent and
-- pooled like tracker shells.
--
-- Reparenting a wired visual moves the engine subtree, which is unverified in
-- combat, so membership changes reconcile through the structural gate and
-- queue while it is closed. Data (tracker.groupId + group.memberOrder) is
-- canonical; ReconcileParenting aligns physical state to it and self-heals at
-- flush, so a blocked pass loses nothing.
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = SAU.Engine
local Groups = {}
SAU.Groups = Groups

local pool = {}       -- array of group entries, session-permanent
local byGroup = {}    -- [gid] = entry
local byFrame = {}    -- [frame] = entry; plain keys, pool frames never die
local parentingDirty = false
local reflowQueued = false

Groups._pool = pool
Groups._byGroup = byGroup
Groups._byFrame = byFrame

-- Grow direction implies orientation: RIGHT/LEFT lay members out
-- horizontally, DOWN/UP vertically. Corner anchors align mixed-size members:
-- horizontal rows share a bottom edge, vertical columns share a left edge, so
-- the group frame (the Edit Mode box) is the true union of its members.
local GROW = {
    RIGHT = { first = "BOTTOMLEFT",  point = "BOTTOMLEFT",  rel = "BOTTOMRIGHT", dx =  1, dy =  0 },
    LEFT  = { first = "BOTTOMRIGHT", point = "BOTTOMRIGHT", rel = "BOTTOMLEFT",  dx = -1, dy =  0 },
    DOWN  = { first = "TOPLEFT",     point = "TOPLEFT",     rel = "BOTTOMLEFT",  dx =  0, dy = -1 },
    UP    = { first = "BOTTOMLEFT",  point = "BOTTOMLEFT",  rel = "TOPLEFT",     dx =  0, dy =  1 },
}
Groups.VALID_GROW = { RIGHT = true, LEFT = true, DOWN = true, UP = true }

function Groups.HasPendingWork()
    return parentingDirty
end

--------------------------------------------------------------------------------
-- Positions ("g<gid>" keys beside the tracker shells' "t<id>" keys)
--------------------------------------------------------------------------------

local function DefaultPositionFor(entry)
    return { point = "CENTER", x = 0, y = 60 + ((entry.index - 1) % 4) * 60 }
end

local function ApplySavedPosition(entry)
    if not entry.occupantId then return end
    local profile = addon.db and addon.db.profile
    local store = profile and rawget(profile, "scootAuraPositions")
    local perKey = store and store["g" .. entry.occupantId]
    local layoutName = Engine.GetActiveLayoutName()
    local pos = layoutName and perKey and perKey[layoutName]
    if not (pos and pos.point) then
        pos = DefaultPositionFor(entry)
    end
    entry.frame:ClearAllPoints()
    entry.frame:SetPoint(pos.point, pos.x or 0, pos.y or 0)
end

function Groups.ApplyPositionsForActiveLayout()
    for _, entry in pairs(byGroup) do
        ApplySavedPosition(entry)
    end
end

--------------------------------------------------------------------------------
-- Edit Mode registration (once per frame, occupant-agnostic)
--------------------------------------------------------------------------------

-- Mirror provider for the branded Edit Mode dialog. Resolved at BUILD time:
-- pool frames are occupant-agnostic and entry.occupantId changes over the
-- session, so the gid is re-read on every build and the spec closures capture
-- the resolved gid. Writes go through the same setter the menu fly-out uses,
-- so the two surfaces cannot drift.
function Groups._EditModeMirror(frame)
    local entry = byFrame[frame]
    local gid = entry and entry.occupantId
    local group = gid and SAU.GetGroup(gid)
    if not group then return nil end

    local specs = {
        -- The menu fly-out's ranges, in the fly-out's order. Short labels on
        -- purpose: the dialog's label budget is ~62px and longer labels run
        -- under the track (the UFZ mirror precedent).
        {
            kind = "slider", label = "Spacing",
            min = 0, max = 50, step = 1, precision = 0,
            get = function()
                local g = SAU.GetGroup(gid)
                return (g and g.settings and g.settings.spacing) or 4
            end,
            set = function(v)
                SAU.SetGroupSettings(gid, { spacing = v })
            end,
        },
        {
            kind = "slider", label = "Scale",
            min = 25, max = 200, step = 5, precision = 0,
            get = function()
                local g = SAU.GetGroup(gid)
                return (g and g.settings and g.settings.scale) or 100
            end,
            set = function(v)
                SAU.SetGroupSettings(gid, { scale = v })
            end,
        },
    }

    -- Rearranging needs at least two members to mean anything.
    local members = 0
    for _, trackerId in ipairs(group.memberOrder or {}) do
        local t = SAU.GetTracker(trackerId)
        if t and t.groupId == gid and t.enabled ~= false then
            members = members + 1
        end
    end

    local R = SAU.Rearrange
    if R and members >= 2 then
        if R.IsActiveFor(gid) then
            specs[#specs + 1] = {
                kind = "status", label = "Rearranging", animate = true,
                buttonLabel = "Done", rebuild = true,
                set = function() R.End() end,
            }
        else
            specs[#specs + 1] = {
                kind = "button", label = "Rearrange Auras", rebuild = true,
                set = function() R.Begin(gid) end,
            }
        end
    end
    return specs
end

local function EnsureLEMFrame(entry)
    if entry.lemRegistered then return end
    local lib = LibStub("LibEditMode", true)
    if not lib then return end
    entry.lemRegistered = true

    local dp = DefaultPositionFor(entry)
    lib:AddFrame(entry.frame, function(frame, layoutName, point, x, y)
        if point and x and y then
            frame:ClearAllPoints()
            frame:SetPoint(point, x, y)
        end
        if layoutName and entry.occupantId then
            local savedPoint, _, _, savedX, savedY = frame:GetPoint(1)
            if savedPoint then
                Engine.SavePosition("g" .. entry.occupantId, layoutName, savedPoint, savedX, savedY)
            else
                Engine.SavePosition("g" .. entry.occupantId, layoutName, point, x, y)
            end
        end
    end, { point = dp.point, x = dp.x, y = dp.y }, nil)

    local Brand = addon.EditMode and addon.EditMode.Brand
    if Brand then
        Brand:Register(entry.frame, { navKey = SAU.NAV_KEY, mirror = Groups._EditModeMirror })
    end

    -- Frames added while Edit Mode is open miss the enter pass; without this
    -- the new frame is undraggable until Edit Mode bounces.
    if lib.isEditing then
        local sel = lib.frameSelections and lib.frameSelections[entry.frame]
        if sel then pcall(sel.ShowHighlighted, sel) end
    end
end

--------------------------------------------------------------------------------
-- Pool
--------------------------------------------------------------------------------

local function CreateEntry()
    local index = #pool + 1
    local frame = CreateFrame("Frame", "ScootAuraGroup" .. index, UIParent)
    addon.Strata.ApplyHUD(frame, 25)
    frame:SetSize(32, 32)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()
    addon.RegisterPetBattleFrame(frame)
    local entry = { index = index, frame = frame }
    pool[index] = entry
    byFrame[frame] = entry
    return entry
end

local function AcquireEntry()
    for _, entry in ipairs(pool) do
        if not entry.occupantId then return entry end
    end
    return CreateEntry()
end

function Groups.ClaimForGroup(gid)
    local group = SAU.GetGroup(gid)
    if not group then return end
    local entry = byGroup[gid]
    if not entry then
        entry = AcquireEntry()
        entry.occupantId = gid
        byGroup[gid] = entry
    end
    entry.frame.editModeName = group.name or ("Aura Group " .. gid)
    EnsureLEMFrame(entry)
    ApplySavedPosition(entry)
    return entry
end

function Groups.ReleaseForGroup(gid)
    local entry = byGroup[gid]
    if not entry then return end
    -- Runtime lookup: rearrange.lua loads after this file.
    local R = SAU.Rearrange
    if R and R.IsActiveFor and R.IsActiveFor(gid) then R.ForceEnd() end
    entry.frame:Hide()
    entry.occupantId = nil
    byGroup[gid] = nil
    Engine.Record("group-released", "g" .. gid)
end

function Groups.UpdateEditModeName(gid)
    local entry = byGroup[gid]
    local group = SAU.GetGroup(gid)
    if entry and group then
        entry.frame.editModeName = group.name or ("Aura Group " .. gid)
    end
end

--------------------------------------------------------------------------------
-- Parenting reconcile (gated)
--------------------------------------------------------------------------------

-- Returns the visual to its shell (standalone form). The visual's own scale
-- and alpha reset to 1: standalone styling applies them to the shell, and a
-- leftover grouped scale would double up. Caller holds the gate.
local function DetachEntry(entry)
    entry.visual:SetParent(entry.shell)
    entry.visual:ClearAllPoints()
    entry.visual:SetAllPoints(entry.shell)
    entry.visual:SetScale(1)
    entry.visual:SetAlpha(1)
    entry.visual:Show()
    entry.grouped = nil
end

--- Aligns physical parenting with data. Returns the list of changed tracker
-- ids, or false when the gate blocked the pass (queued for flush).
function Groups.ReconcileParenting()
    if not Engine.CanDoStructuralWork() then
        parentingDirty = true
        Engine.Record("group-parenting-queued", "")
        return false
    end
    parentingDirty = false

    local changed = {}
    for trackerId, entry in pairs(Engine._byTracker) do
        local tracker = SAU.GetTracker(trackerId)
        local gid = tracker and tracker.groupId
        local gentry = gid and byGroup[gid] or nil
        if gentry then
            if not entry.grouped or entry.visual:GetParent() ~= gentry.frame then
                entry.visual:SetParent(gentry.frame)
                entry.visual:ClearAllPoints()
                entry.visual:Show()
                entry.grouped = true
                entry.shell:Hide()
                table.insert(changed, trackerId)
            end
        elseif entry.grouped then
            DetachEntry(entry)
            table.insert(changed, trackerId)
        end
    end

    -- Unoccupied pool entries must never stay parented into a group: the next
    -- claim would render its tracker inside the old group's frame.
    for _, entry in ipairs(Engine._pool) do
        if not entry.occupantId and entry.grouped then
            DetachEntry(entry)
        end
    end
    return changed
end

--- Physical cleanup when a tracker's pool entry is released while grouped.
-- The visual hides immediately (a parked container must not linger visible in
-- the group); the reparent itself waits on the gate when blocked.
function Groups.OnEntryReleased(entry)
    if not entry.grouped then return end
    entry.visual:Hide()
    if Engine.CanDoStructuralWork() then
        DetachEntry(entry)
    else
        parentingDirty = true
    end
    Groups.RequestReflow()
end

--------------------------------------------------------------------------------
-- Layout (pure Scoot frame work, legal in combat)
--------------------------------------------------------------------------------

--- Anchors one group's member visuals and sizes the group frame. Member sizes
-- come from the engine's stored host sizes and the scale setting, never from
-- widget reads. Disabled members are skipped; the rest close the gap.
function Groups.LayoutGroup(gid)
    local entry = byGroup[gid]
    local group = SAU.GetGroup(gid)
    if not entry or not group then return end

    local settings = group.settings or {}
    local spacing = tonumber(settings.spacing) or 4
    local grow = GROW[settings.grow] or GROW.RIGHT
    local horizontal = (grow.dy == 0)

    -- Group scale multiplies member scales through parent inheritance; the
    -- spacing setting lives in group space, so the on-screen gap scales too.
    local groupScale = math.max((tonumber(settings.scale) or 100) / 100, 0.25)
    entry.frame:SetScale(groupScale)

    local prev
    local totalMain, maxCross, count = 0, 0, 0
    for _, trackerId in ipairs(group.memberOrder or {}) do
        local tentry = Engine._byTracker[trackerId]
        local tracker = SAU.GetTracker(trackerId)
        if tentry and tentry.grouped and tracker and tracker.groupId == gid
            and tracker.enabled ~= false then
            local db = SAU.GetDB(trackerId)
            local scale = math.max((tonumber(db and db.scale) or 100) / 100, 0.25)
            local w = tentry.hostW or 32
            local h = tentry.hostH or 32
            tentry.visual:SetSize(w, h)
            tentry.visual:ClearAllPoints()
            if not prev then
                tentry.visual:SetPoint(grow.first, entry.frame, grow.first, 0, 0)
            else
                -- SetPoint offsets live in the member's own scaled space; divide
                -- so the on-screen gap matches the setting.
                local off = spacing / scale
                tentry.visual:SetPoint(grow.point, prev, grow.rel, off * grow.dx, off * grow.dy)
            end
            prev = tentry.visual
            count = count + 1
            local physW, physH = w * scale, h * scale
            local main = horizontal and physW or physH
            local cross = horizontal and physH or physW
            totalMain = totalMain + main + ((count > 1) and spacing or 0)
            maxCross = math.max(maxCross, cross)
        end
    end

    if count == 0 then
        totalMain, maxCross = 32, 32
    end
    if horizontal then
        entry.frame:SetSize(totalMain, maxCross)
    else
        entry.frame:SetSize(maxCross, totalMain)
    end

    -- Empty groups stay positionable in Edit Mode and invisible outside it.
    local editing = SAU._isEditModeActive and SAU._isEditModeActive() or false
    entry.frame:SetShown(count > 0 or editing)
end

function Groups.ReflowAll()
    for gid in pairs(byGroup) do
        Groups.LayoutGroup(gid)
    end
end

--- Coalesced deferred reflow: host-size changes arrive one member at a time
-- during styling passes.
function Groups.RequestReflow()
    if reflowQueued then return end
    reflowQueued = true
    C_Timer.After(0, function()
        reflowQueued = false
        Groups.ReflowAll()
    end)
end

--------------------------------------------------------------------------------
-- Top-level passes
--------------------------------------------------------------------------------

--- Aligns the group pool with the store: claims live groups, releases stale
-- entries, reconciles member parenting, and lays everything out.
function Groups.ApplyAll()
    local groups = SAU.IsModuleActive() and SAU.OwnedGroups() or {}

    local toRelease = {}
    for gid in pairs(byGroup) do
        if not groups[gid] then table.insert(toRelease, gid) end
    end
    for _, gid in ipairs(toRelease) do
        Groups.ReleaseForGroup(gid)
    end
    for gid in pairs(groups) do
        Groups.ClaimForGroup(gid)
    end

    Groups.ReconcileParenting()
    Groups.ReflowAll()
end

--- The one call membership edits route through: physical state follows data,
-- then every tracker restyles against its new home (shell or group frame).
function Groups.ApplyMembership()
    Groups.ApplyAll()
    SAU.RebuildAll()
end

--- Runs from Engine.FlushPending once the structural gate reopens.
function Groups.FlushPending()
    if not parentingDirty then return end
    local changed = Groups.ReconcileParenting()
    if not changed then return end
    Groups.ReflowAll()
    for _, trackerId in ipairs(changed) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and SAU._ApplyStyling then
            SAU._ApplyStyling(trackerId, tracker)
        end
    end
end

--------------------------------------------------------------------------------
-- Ungroup position snap
--------------------------------------------------------------------------------

--- Places the shell where the grouped visual currently renders, so ungrouping
-- puts the tracker back exactly where the user sees it. Persisted per layout.
-- Must run before the reparent (the visual's rect is read while it still sits
-- in the group).
function Groups.SnapShellToVisual(trackerId)
    local entry = Engine._byTracker[trackerId]
    if not entry or not entry.grouped then return end

    -- The shell's scale can be stale while grouped (styling targets the
    -- visual); set it from the setting first so the offset math lands in the
    -- scale space the shell will actually use.
    local db = SAU.GetDB(trackerId)
    local scale = math.max(((db and db.scale) or 100) / 100, 0.25)
    entry.shell:SetScale(scale)

    local ok, x, y = pcall(function()
        local left, bottom = entry.visual:GetLeft(), entry.visual:GetBottom()
        if type(left) ~= "number" or type(bottom) ~= "number" then return nil end
        local vs = entry.visual:GetEffectiveScale()
        local ss = entry.shell:GetEffectiveScale()
        return left * vs / ss, bottom * vs / ss
    end)
    if not ok or type(x) ~= "number" or issecretvalue(x)
        or type(y) ~= "number" or issecretvalue(y) then
        return
    end

    entry.shell:ClearAllPoints()
    entry.shell:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    local layoutName = Engine.GetActiveLayoutName()
    if layoutName then
        Engine.SavePosition("t" .. trackerId, layoutName, "BOTTOMLEFT", x, y)
    end
end
