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
local SS = addon.SecretSafe
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

-- Grow direction implies orientation: RIGHT/LEFT/CENTER lay members out
-- horizontally, DOWN/UP vertically. Corner anchors align mixed-size members:
-- horizontal rows share a bottom edge, vertical columns share a left edge, so
-- the group frame (the Edit Mode box) is the true union of its members.
--
-- `axis` and `pin` name the edge the group frame holds still when its member
-- set changes, as a rect fraction on the main axis (0 left or bottom, 1 right
-- or top): a row growing RIGHT keeps its left edge, LEFT its right edge, DOWN
-- its top, UP its bottom. CENTER is a RIGHT row that keeps its center.
local GROW = {
    RIGHT  = { first = "BOTTOMLEFT",  point = "BOTTOMLEFT",  rel = "BOTTOMRIGHT", dx =  1, dy =  0, axis = "x", pin = 0 },
    LEFT   = { first = "BOTTOMRIGHT", point = "BOTTOMRIGHT", rel = "BOTTOMLEFT",  dx = -1, dy =  0, axis = "x", pin = 1 },
    CENTER = { first = "BOTTOMLEFT",  point = "BOTTOMLEFT",  rel = "BOTTOMRIGHT", dx =  1, dy =  0, axis = "x", pin = 0.5 },
    DOWN   = { first = "TOPLEFT",     point = "TOPLEFT",     rel = "BOTTOMLEFT",  dx =  0, dy = -1, axis = "y", pin = 1 },
    UP     = { first = "BOTTOMLEFT",  point = "BOTTOMLEFT",  rel = "TOPLEFT",     dx =  0, dy =  1, axis = "y", pin = 0 },
}
Groups.VALID_GROW = { RIGHT = true, LEFT = true, CENTER = true, DOWN = true, UP = true }

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
    addon.EditMode.RestorePositionable(entry.frame, Engine.GetActiveLayoutName())
end

function Groups.ApplyPositionsForActiveLayout()
    for _, entry in pairs(byGroup) do
        ApplySavedPosition(entry)
    end
end

--------------------------------------------------------------------------------
-- The pinned edge
--------------------------------------------------------------------------------

-- [up fraction][across fraction] -> anchor point, the inverse of
-- addon.EditMode.AnchorFraction.
local POINT_BY_FRACTION = {
    [0]   = { [0] = "BOTTOMLEFT", [0.5] = "BOTTOM", [1] = "BOTTOMRIGHT" },
    [0.5] = { [0] = "LEFT",       [0.5] = "CENTER", [1] = "RIGHT" },
    [1]   = { [0] = "TOPLEFT",    [0.5] = "TOP",    [1] = "TOPRIGHT" },
}

-- How long after a claim the group's size is taken as final. Host sizes
-- arrive a member at a time over the first styling passes, and text metrics
-- a frame behind those.
local SETTLE_SECONDS = 2
local SETTLE_TRIES = 10

--- The group frame's anchor re-expressed on the edge its grow direction
-- pins, the frame staying where it is: point, x, y, or nil when the anchor
-- already sits on the pin or cannot be read. LibEditMode picks the anchor by
-- screen region at every drop, so a row near the middle of the screen would
-- resize about its center and one near an edge about that edge, whatever the
-- direction says. The frame hangs off UIParent by one point, offsets in its
-- own scale (positionables.lua), so the same rect on another point is
-- x + (fx - gx) * (W - w * s) / s,  and y alike.
local function ResolvePin(entry, grow)
    local frame = entry.frame
    local ok, point, _, _, x, y = pcall(frame.GetPoint, frame, 1)
    if not ok then return nil end
    point = SS.plainString(point)
    x, y = SS.safeNumber(x), SS.safeNumber(y)
    local from = point and addon.EditMode.AnchorFraction(point)
    if not (from and x and y) then return nil end

    local fx, fy = from[1], from[2]
    local gx, gy = fx, fy
    if grow.axis == "x" then gx = grow.pin else gy = grow.pin end
    if gx == fx and gy == fy then return nil end

    local okSize, w, h = pcall(frame.GetSize, frame)
    local okScale, s = pcall(frame.GetScale, frame)
    w, h = okSize and SS.safeNumber(w) or nil, okSize and SS.safeNumber(h) or nil
    s = okScale and SS.safeNumber(s) or nil
    if not (w and h and s and s > 0) then return nil end
    local W, H = UIParent:GetSize()

    return POINT_BY_FRACTION[gy][gx],
        x + (fx - gx) * (W - w * s) / s,
        y + (fy - gy) * (H - h * s) / s
end

--- Moves the anchor onto the pin and saves it under the active layout. The
-- frame's size must be the one the player sees the group at: the pin is
-- worked out from it. A no-op once the anchor is on the pin.
local function PinAnchor(entry, gid, grow)
    local point, x, y = ResolvePin(entry, grow)
    if not point then return end
    entry.frame:ClearAllPoints()
    entry.frame:SetPoint(point, x, y)
    local layoutName = Engine.GetActiveLayoutName()
    if gid and layoutName then
        Engine.SavePosition("g" .. gid, layoutName, point, x, y)
    end
end

--- One more layout pass after the settle delay, for a group whose anchor is
-- off its pin while its size is still arriving. Capped per claim: a group
-- that never settles stops asking.
local function RequestSettle(entry)
    if entry.settlePending or (entry.settleTries or 0) >= SETTLE_TRIES then return end
    entry.settlePending = true
    entry.settleTries = (entry.settleTries or 0) + 1
    C_Timer.After(SETTLE_SECONDS, function()
        entry.settlePending = nil
        if entry.occupantId then Groups.LayoutGroup(entry.occupantId) end
    end)
end

-- The positionable's apply hook. A drop lands on LibEditMode's anchor; it
-- moves onto the pin here, while the frame has the size the player dragged,
-- and positionables.lua then stores what GetPoint reports. A restore applies
-- the record as stored: the frame's size may not be this occupant's yet, and
-- LayoutGroup pins once it has settled.
local function ApplyGroupPosition(frame, point, x, y, reason)
    frame:ClearAllPoints()
    frame:SetPoint(point, x, y)
    if reason ~= "drop" then return end
    local entry = byFrame[frame]
    local gid = entry and entry.occupantId
    local group = gid and SAU.GetGroup(gid)
    if not group then return end
    local settings = group.settings or {}
    PinAnchor(entry, gid, GROW[settings.grow] or GROW.RIGHT)
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
    -- An unloaded group has no Edit Mode presence, so it offers no controls.
    if not SAU.IsGroupActive(gid, group) then return nil end

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
        {
            kind = "selector", label = "Alignment",
            values = addon.Catalogs.GrowDirection.values,
            order = addon.Catalogs.GrowDirection.order,
            get = function()
                local g = SAU.GetGroup(gid)
                local grow = g and g.settings and g.settings.grow
                return Groups.VALID_GROW[grow] and grow or "RIGHT"
            end,
            set = function(v)
                SAU.SetGroupSettings(gid, { grow = v })
            end,
        },
    }

    -- Rearranging needs at least two members to mean anything.
    local members = 0
    for _, trackerId in ipairs(group.memberOrder or {}) do
        local t = SAU.GetTracker(trackerId)
        if t and t.groupId == gid and SAU.IsTrackerActive(trackerId, t) then
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

-- One positionable per group frame (core/editmode/positionables.lua). Storage
-- stays positions["g" .. gid][layoutName], beside the tracker shells' keys.
local function EnsureLEMFrame(entry)
    if entry.lemRegistered then return end
    local selection = addon.EditMode.RegisterPositionable(entry.frame, {
        key = function() return entry.occupantId and ("g" .. entry.occupantId) or nil end,
        default = DefaultPositionFor(entry),
        store = { get = Engine._GetStoredPosition, set = Engine.SavePosition },
        apply = ApplyGroupPosition,
        restoreDefault = true,
        brand = { navKey = SAU.NAV_KEY, mirror = Groups._EditModeMirror },
    })
    entry.lemRegistered = selection ~= nil
end

--------------------------------------------------------------------------------
-- Pool
--------------------------------------------------------------------------------

local function CreateEntry()
    local index = #pool + 1
    local frame = CreateFrame("Frame", addon.Brand .. "AuraGroup" .. index, UIParent)
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

-- Kept off addon.Pool: slot allocator; acquire scans occupantId over named frames registered once with Edit Mode.
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
        entry.claimedAt = GetTime()
        entry.settleTries = 0
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
    -- The size on the frame stops being anyone's: the next occupant settles
    -- its own before its anchor is pinned (LayoutGroup).
    entry.sizeW, entry.sizeH, entry.growKey = nil, nil, nil
    -- Runtime lookup: slots.lua loads after this file.
    if SAU.Slots then SAU.Slots.Release(entry) end
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
-- `plainChain` keeps the members off the state-driven chain (slots.lua) for
-- this pass, for a caller about to read a member's rect.
function Groups.LayoutGroup(gid, plainChain)
    local entry = byGroup[gid]
    local group = SAU.GetGroup(gid)
    if not entry or not group then return end

    local settings = group.settings or {}
    local spacing = tonumber(settings.spacing) or 4
    local grow = GROW[settings.grow] or GROW.RIGHT
    local horizontal = (grow.dy == 0)

    -- A change of direction moves the pin. The frame still has the size the
    -- player sees it at, so the anchor moves across before the size does.
    local growKey = GROW[settings.grow] and settings.grow or "RIGHT"
    if entry.growKey and entry.growKey ~= growKey then
        PinAnchor(entry, gid, grow)
    end
    entry.growKey = growKey

    -- Group scale multiplies member scales through parent inheritance; the
    -- spacing setting lives in group space, so the on-screen gap scales too.
    local groupScale = math.max((tonumber(settings.scale) or 100) / 100, 0.25)
    entry.frame:SetScale(groupScale)

    local editing = SAU._isEditModeActive and SAU._isEditModeActive() or false
    local Cooldown = SAU.Cooldown

    -- Every loaded member in order. `included` is whether the plain gates
    -- admit it now: a member hidden by its combat gate gives up its slot, the
    -- same as a disabled one, and so does a cooldown whose spell the
    -- character does not know, so the rest close the gap. The frame is sized
    -- to the included members.
    local members = {}
    local totalMain, maxCross, count = 0, 0, 0
    local allSized = true
    for _, trackerId in ipairs(group.memberOrder or {}) do
        local tentry = Engine._byTracker[trackerId]
        local tracker = SAU.GetTracker(trackerId)
        if tentry and tentry.grouped and tracker and tracker.groupId == gid
            and SAU.IsTrackerActive(trackerId, tracker) then
            local db = SAU.GetDB(trackerId)
            local scale = math.max((tonumber(db and db.scale) or 100) / 100, 0.25)
            local w = tentry.hostW or 32
            local h = tentry.hostH or 32
            local physW, physH = w * scale, h * scale
            local main = horizontal and physW or physH
            local cross = horizontal and physH or physW
            -- A Weapon Buff reminder is dark while the weapons are buffed, and
            -- that verdict is plain, so it gives its slot up here.
            local included = SAU.CombatGateOpen(tracker)
                and (editing or not Cooldown or Cooldown.HoldsSlot(trackerId))
                and (editing or not SAU.Missing or SAU.Missing.HoldsSlot(trackerId))
            members[#members + 1] = {
                trackerId = trackerId, tracker = tracker, tentry = tentry,
                scale = scale, main = main, included = included,
            }
            if included then
                if not (tentry.hostW and tentry.hostH) then allSized = false end
                tentry.visual:SetSize(w, h)
                count = count + 1
                totalMain = totalMain + main + ((count > 1) and spacing or 0)
                maxCross = math.max(maxCross, cross)
            end
        end
    end

    -- Members that can show nothing hang on a chain the client moves by
    -- their state (slots.lua). It answers false for a group with no such
    -- member, with Edit Mode open, and while it cannot be built; the plain
    -- chain below stands then, each visual on the one before it.
    local Slots = SAU.Slots
    local onChain = Slots ~= nil and not plainChain
        and Slots.Layout(entry, members, growKey, spacing)
    if not onChain then
        local prev
        for _, m in ipairs(members) do
            if m.included then
                local visual = m.tentry.visual
                visual:ClearAllPoints()
                if not prev then
                    visual:SetPoint(grow.first, entry.frame, grow.first, 0, 0)
                else
                    -- SetPoint offsets live in the member's own scaled space;
                    -- divide so the on-screen gap matches the setting.
                    local off = spacing / m.scale
                    visual:SetPoint(grow.point, prev, grow.rel, off * grow.dx, off * grow.dy)
                end
                prev = visual
            end
        end
    end

    if count == 0 then
        totalMain, maxCross = 32, 32
    end
    local frameW = horizontal and totalMain or maxCross
    local frameH = horizontal and maxCross or totalMain

    -- An anchor off its pin here is a record saved before edges were pinned,
    -- or under another layout while the direction differed. It moves across
    -- only once the group's size has settled: this pass computes the size
    -- the last one set, every member has reported a host size, no reparent
    -- is queued, and the claim is a moment old. Pinned against a size still
    -- arriving, the group would land off where it stood. Until then the
    -- frame resizes about the anchor it has, as it always did.
    local settled = count > 0 and allSized and not parentingDirty
        and entry.sizeW == frameW and entry.sizeH == frameH
        and (GetTime() - (entry.claimedAt or 0)) >= SETTLE_SECONDS
    entry.frame:SetSize(frameW, frameH)
    entry.sizeW, entry.sizeH = frameW, frameH
    if settled then
        PinAnchor(entry, gid, grow)
    elseif count > 0 and ResolvePin(entry, grow) then
        RequestSettle(entry)
    end

    -- Empty groups stay positionable in Edit Mode and invisible outside it. A
    -- group gated out by its specs lays out zero members and so reads as empty,
    -- but it must not appear in Edit Mode either: an unloaded group is not
    -- draggable and shows no preview.
    local wasShown = entry.frame:IsShown()
    local shown = SAU.IsGroupActive(gid, group) and (count > 0 or editing)
    entry.frame:SetShown(shown)
    -- A container processes only while shown: the spacers under a frame that
    -- was hidden have parsed nothing since.
    if shown and not wasShown and onChain then Slots.KickUnit(nil) end
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
    local groups = {}
    if SAU.IsModuleActive() then
        for gid, group in pairs(SAU.AllGroups()) do
            if SAU.IsGroupActive(gid, group) then groups[gid] = group end
        end
    end

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
    if not parentingDirty then
        -- Spacer containers that waited on the gate are built by a layout pass.
        if SAU.Slots and SAU.Slots.HasPendingWork() then Groups.ReflowAll() end
        return
    end
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

    -- A visual on the state-driven chain has no plain rect to read; one pass
    -- on the plain chain puts it where it stands with every slot open. The
    -- membership change that follows lays the group out again.
    local tracker = SAU.GetTracker(trackerId)
    if tracker and tracker.groupId then
        Groups.LayoutGroup(tracker.groupId, true)
    end

    -- The shell's scale can be stale while grouped (styling targets the
    -- visual); set it from the setting first so the offset math lands in the
    -- scale space the shell will use.
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
