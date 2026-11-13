-- scootauras/slots.lua - Group slots that follow state
--
-- A group member that shows nothing gives up its slot: a buff icon whose aura
-- is down, a cooldown its "Show it..." rule hides, an ability that cannot be
-- cast. None of those states can be read in combat, so the layout never
-- branches on one. Each such member owns a spacer the client sizes:
--
--   aura   an AuraContainer with one aura group on the member's unit, filter
--          and include set. Blizzard's flow layout sizes the container to its
--          present auras with a floor of 1, so it is slot + 1 long while the
--          aura is up and 1 while it is not (the missing.lua gate, resized).
--   bool   a StatusBar fed the member's ready or usable state as a number
--          (Cooldown.SlotValue). Its fill is slot + 2 long while the member
--          shows and 2 while it does not.
--
-- The members hang on a chain of joints, 1 x 1 frames, one per member:
--
--   box edge -- joint 1 -- spacer 1 -- joint 2 -- spacer 2 -- joint 3 ...
--                  |                      |                      |
--              visual 1               visual 2               visual 3
--
-- A joint anchors to the far end of the spacer before it, less that spacer's
-- floor. A member that always shows has no spacer and the next joint takes a
-- plain offset. A spacer sits on its own member's joint for as long as it
-- lives, so a change in which members take part, a combat gate opening
-- mid-fight, re-anchors joints and visuals alone, and those are Scoot
-- frames. Container work waits on the structural gate; a member whose spacer
-- is not built yet holds its slot.
--
-- A centered row measures itself first. A second chain runs left from the
-- box's center with every length halved, and the display chain starts where
-- it ends: half the row's width left of center.
--
-- The group frame is not on the chain. It keeps the plain size of every
-- member the plain gates admit (groups.lua) and stays the Edit Mode box.
-- With Edit Mode open the group lays out on its plain chain, where every
-- member previews and Rearrange reads plain rects.
--
-- A frame anchors to a group-sized container, or to anything anchored to
-- one, only when it carries ForbiddenAspect.UntrustedLayoutScriptExecution.
-- The joints and the bars are created through Engine.CreateLayoutFrame, as
-- the member visuals are (engine.lua).
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = SAU.Engine
local Slots = {}
SAU.Slots = Slots

-- The flow layout's floor for a container that placed nothing.
local AURA_FLOOR = 1
-- A fill this long keeps a rect at any scale; a region 0 long has none, and
-- an anchor to it is undefined.
local BAR_FLOOR = 2

-- Chain geometry per direction. `near` is the corner a slot starts from and
-- `far` the corner it ends at, both on the edge the members share.
local DIRS = {
    RIGHT = { near = "BOTTOMLEFT",  far = "BOTTOMRIGHT", dx =  1, dy =  0 },
    LEFT  = { near = "BOTTOMRIGHT", far = "BOTTOMLEFT",  dx = -1, dy =  0 },
    DOWN  = { near = "TOPLEFT",     far = "BOTTOMLEFT",  dx =  0, dy = -1 },
    UP    = { near = "BOTTOMLEFT",  far = "TOPLEFT",     dx =  0, dy =  1 },
}

-- Session switch, flipped by the debug command.
local enabled = true
-- Set when an anchor onto the chain was refused; the chain is not tried
-- again this session.
local refused
local spacerSeq = 0

-- [trackerId] = record, for the members with a bool spacer (Feed).
local boolRecords = {}
-- [spacer] = true, for every aura spacer not retired (KickUnit).
local auraSpacers = {}

--------------------------------------------------------------------------------
-- Per-group state
--------------------------------------------------------------------------------

local function EnsureState(gentry)
    local s = gentry.slots
    if not s then
        s = { records = {}, freeRoles = {}, retired = 0 }
        gentry.slots = s
    end
    return s
end

-- One role of one member: a joint, and whichever spacers the member has
-- needed on it. `display` roles carry the visual; `measure` roles exist on a
-- centered row.
local function NewRole(gentry, s)
    local role = table.remove(s.freeRoles)
    if role then return role end
    local joint, slotReady = Engine.CreateLayoutFrame("Frame", gentry.frame)
    joint:SetSize(1, 1)
    joint:EnableMouse(false)
    return { joint = joint, slotReady = slotReady }
end

local function NewRecord(gentry, s)
    local rec = { display = NewRole(gentry, s), measure = NewRole(gentry, s) }
    rec.roles = { rec.display, rec.measure }
    return rec
end

--------------------------------------------------------------------------------
-- Aura spacers
--------------------------------------------------------------------------------

-- Group frames exist to be counted by the flow layout, which reads the
-- element size from the group's options and never from the frame.
local function InitGateFrame(button)
    pcall(button.SetSize, button, 1, 1)
    pcall(button.EnableMouse, button, false)
    pcall(button.SetMouseClickEnabled, button, false)
    pcall(button.SetMouseMotionEnabled, button, false)
end

local function AuraLayoutOptions(length, vertical)
    if vertical then
        return { elementWidth = 1, elementHeight = length + AURA_FLOOR }
    end
    return { elementWidth = length + AURA_FLOOR, elementHeight = 1 }
end

--- Whether the member's own container is built for the content the tracker
-- holds now. The spacer copies its unit and include set, so it waits for it.
local function DisplayBuilt(tracker, tentry)
    return tentry.container ~= nil and tentry.wiredFilters ~= nil
        and tentry.wiredFilterKey ~= nil and not tentry.filtersStale
        and tentry.wiredSpellId == tracker.spellId
        and tentry.wiredKind == tracker.kind
        and tentry.wiredUnit == SAU.EngineUnitFor(tracker)
end

local function ContentKey(tracker, tentry)
    return tostring(tentry.wiredUnit) .. "|" .. SAU.FilterForKind(tracker.kind)
        .. "|" .. tostring(tentry.wiredFilterKey)
end

-- A container cannot be destroyed and its group cannot be removed, so a
-- spacer that no longer fits is switched off and left on the group frame.
local function RetireAura(s, role)
    local a = role.aura
    if not a then return end
    pcall(a.container.SetEnabled, a.container, false)
    pcall(a.container.Hide, a.container)
    auraSpacers[a] = nil
    role.aura = nil
    s.retired = s.retired + 1
end

local function ParkAura(role)
    local a = role.aura
    if not a or a.parked then return end
    pcall(a.container.SetEnabled, a.container, false)
    a.parked = true
end

--- The role's aura spacer, at this direction and length, for the content the
-- member's own container is wired to. Builds, re-points the anchor and the
-- length, or revives a parked one. Building and re-pointing need the
-- structural gate: nil means the member holds its slot for now, and
-- `s.pending` asks for another pass once the gate opens.
local function EnsureAura(gentry, s, role, tracker, tentry, trackerId, dirKey, length)
    local dir = DIRS[dirKey]
    local vertical = dir.dx == 0
    local key = ContentKey(tracker, tentry)
    local a = role.aura

    if a and a.contentKey == key then
        if a.dirKey ~= dirKey or a.length ~= length then
            if not Engine.CanDoStructuralWork() then
                s.pending = true
                return nil
            end
            local c = a.container
            local okLayout = pcall(c.SetAuraGroupLayout, c, a.groupKey, AuraLayoutOptions(length, vertical))
            local okAnchor = okLayout and pcall(c.ClearAllPoints, c)
                and pcall(c.SetPoint, c, dir.near, role.joint, dir.near, 0, 0)
            if okAnchor then
                a.dirKey, a.length = dirKey, length
            else
                RetireAura(s, role)
                a = nil
            end
        end
        if a then
            if a.parked then
                pcall(a.container.SetEnabled, a.container, true)
                pcall(a.container.UpdateAllAuras, a.container)
                a.parked = nil
            end
            return a
        end
    end

    if not Engine.CanDoStructuralWork() then
        s.pending = true
        return nil
    end
    RetireAura(s, role)

    local ok, container = pcall(CreateFrame, "AuraContainer", nil, gentry.frame, "CustomAuraContainerTemplate")
    if not ok or not container then
        Engine._SetResult("slot.t" .. trackerId, "container FAILED: " .. Engine._SafeToString(container))
        return nil
    end
    pcall(container.SetSize, container, 1, 1)
    pcall(container.EnableMouse, container, false)

    spacerSeq = spacerSeq + 1
    local groupKey = "scootSlot" .. spacerSeq
    -- The group first: it gives the container the aspect the joint carries,
    -- without which the anchor below is refused.
    local okGroup, err = pcall(container.AddAuraGroup, container, groupKey, SAU.FilterForKind(tracker.kind), {
        candidateFilters = tentry.wiredFilters,
        maxFrameCount = 1,
        layout = AuraLayoutOptions(length, vertical),
        initializeFrame = InitGateFrame,
    })
    local okAnchor
    if okGroup then
        okAnchor, err = pcall(container.SetPoint, container, dir.near, role.joint, dir.near, 0, 0)
    end
    if not (okGroup and okAnchor) then
        pcall(container.SetEnabled, container, false)
        pcall(container.Hide, container)
        s.retired = s.retired + 1
        Engine._SetResult("slot.t" .. trackerId,
            (okGroup and "anchor" or "group") .. " FAILED: " .. Engine._SafeToString(err))
        return nil
    end
    -- Unit last, then one kick to sync against the auras standing now.
    pcall(container.SetUnit, container, tentry.wiredUnit)
    pcall(container.UpdateAllAuras, container)

    a = {
        container = container, groupKey = groupKey, contentKey = key,
        dirKey = dirKey, length = length, unit = tentry.wiredUnit,
    }
    role.aura = a
    auraSpacers[a] = true
    Engine._SetResult("slot.t" .. trackerId, "aura spacer (" .. groupKey .. ")")
    return a
end

--------------------------------------------------------------------------------
-- Bool spacers
--------------------------------------------------------------------------------

--- The role's bar, at this direction and length. Every part is a Scoot
-- frame, so this is legal in combat. nil when the bar could not take the
-- aspect or has no fill texture to anchor to.
local function EnsureBar(gentry, role, dirKey, length)
    local b = role.bar
    if not b then
        local bar, slotReady = Engine.CreateLayoutFrame("StatusBar", gentry.frame)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetStatusBarColor(0, 0, 0, 0)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar:EnableMouse(false)
        local tex = bar:GetStatusBarTexture()
        if tex then
            -- The fill's far edge is the next member's place; a snapped edge
            -- would move it by up to half a pixel.
            tex:SetSnapToPixelGrid(false)
            tex:SetTexelSnappingBias(0)
        end
        b = { bar = bar, tex = tex, slotReady = slotReady }
        role.bar = b
    end
    if not (b.tex and b.slotReady) then return nil end

    if b.dirKey ~= dirKey or b.length ~= length then
        local dir = DIRS[dirKey]
        local vertical = dir.dx == 0
        local long = length + BAR_FLOOR
        b.bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        -- The fill starts at the near corner: a bar fills from its left or
        -- its bottom unless reversed.
        b.bar:SetReverseFill(dirKey == "LEFT" or dirKey == "DOWN")
        b.bar:SetSize(vertical and 1 or long, vertical and long or 1)
        b.bar:ClearAllPoints()
        if not pcall(b.bar.SetPoint, b.bar, dir.near, role.joint, dir.near, 0, 0) then
            b.dirKey, b.length = nil, nil
            return nil
        end
        b.dirKey, b.length = dirKey, length
        b.closed = BAR_FLOOR / long
    end
    b.bar:Show()
    b.live = true
    return b
end

local function ParkBar(role)
    local b = role.bar
    if not b or not b.live then return end
    b.bar:Hide()
    b.live = nil
end

--- Writes the member's state to its bars: 1 while it shows, the floor's
-- share while it does not. Called by cooldown.lua on every cooldown and
-- usable event, and at layout. The value may be secret; it goes to SetValue
-- and nowhere else.
function Slots.Feed(trackerId)
    local rec = boolRecords[trackerId]
    if not rec then return end
    local Cooldown = SAU.Cooldown
    for _, role in ipairs(rec.roles) do
        local b = role.bar
        if b and b.live then
            local value = Cooldown and Cooldown.SlotValue(trackerId, 1, b.closed)
            if type(value) ~= "number" then value = 1 end
            pcall(b.bar.SetValue, b.bar, value)
        end
    end
end

--------------------------------------------------------------------------------
-- Records
--------------------------------------------------------------------------------

-- A member that left the layout for now (its spec, its switch) keeps its
-- spacers switched off, and a return revives them.
local function ParkRecord(trackerId, rec)
    for _, role in ipairs(rec.roles) do
        ParkAura(role)
        ParkBar(role)
    end
    boolRecords[trackerId] = nil
end

local function ParkAll(gentry)
    local s = gentry.slots
    if not s then return end
    for trackerId, rec in pairs(s.records) do
        ParkRecord(trackerId, rec)
    end
    s.active = nil
    s.pending = nil
end

--- The group frame is changing occupant: its aura spacers match no one any
-- more, and its joints and bars go back for the next group's members.
function Slots.Release(gentry)
    local s = gentry and gentry.slots
    if not s then return end
    for trackerId, rec in pairs(s.records) do
        for _, role in ipairs(rec.roles) do
            RetireAura(s, role)
            ParkBar(role)
            role.joint:ClearAllPoints()
            role.joint:SetPoint("CENTER", gentry.frame, "CENTER", 0, 0)
            s.freeRoles[#s.freeRoles + 1] = role
        end
        boolRecords[trackerId] = nil
    end
    s.records = {}
    s.active = nil
    s.pending = nil
end

--------------------------------------------------------------------------------
-- The chain
--------------------------------------------------------------------------------

--- Anchors each taking-part member's joint for one role along a direction,
-- from the cursor (ref, point, x, y), and returns ok and the cursor past the
-- last member. `attach` also puts each member's visual on its joint.
local function RunChain(members, roleName, dirKey, attach, ref, point, x, y)
    local dir = DIRS[dirKey]
    for _, m in ipairs(members) do
        if m.included then
            local role = m.rec[roleName]
            local joint = role.joint
            joint:ClearAllPoints()
            if not pcall(joint.SetPoint, joint, dir.near, ref, point, x, y) then
                return false
            end
            if attach then
                local visual = m.tentry.visual
                visual:ClearAllPoints()
                if not pcall(visual.SetPoint, visual, dir.near, joint, dir.near, 0, 0) then
                    return false
                end
            end

            local spacer = m.spacers and m.spacers[roleName]
            if spacer and spacer.container then
                ref, point = spacer.container, dir.far
                x, y = -AURA_FLOOR * dir.dx, -AURA_FLOOR * dir.dy
            elseif spacer and spacer.tex then
                ref, point = spacer.tex, dir.far
                x, y = -BAR_FLOOR * dir.dx, -BAR_FLOOR * dir.dy
            else
                local length = m.length * (roleName == "measure" and 0.5 or 1)
                ref, point = joint, dir.near
                x, y = length * dir.dx, length * dir.dy
            end
        end
    end
    return true, ref, point, x, y
end

--- Whether this group lays out on the chain at all: some loaded member gives
-- up its slot by state, every member's visual can hang on a spacer, and no
-- member is a reminder (its click overlay is placed from a plain rect).
local function Wanted(members)
    if not enabled or refused then return false end
    if SAU._isEditModeActive and SAU._isEditModeActive() then return false end
    local dynamic = false
    for _, m in ipairs(members) do
        local source = SAU.SlotSource(m.tracker)
        if source == "missing" or not m.tentry.slotReady then return false end
        if source ~= "fixed" then dynamic = true end
        m.source = source
    end
    return dynamic
end

--- Places a group's members on the chain. `members` is every loaded member
-- in order, each { trackerId, tracker, tentry, main, included }: `main` its
-- length along the row in group space, `included` whether the plain gates
-- admit it now. Returns true when the visuals are placed; false leaves them
-- to the caller's plain chain.
function Slots.Layout(gentry, members, growKey, spacing)
    if not Wanted(members) then
        if gentry.slots and gentry.slots.active then ParkAll(gentry) end
        return false
    end

    local s = EnsureState(gentry)
    s.pending = nil
    local centered = growKey == "CENTER"
    local dirKey = DIRS[growKey] and growKey or "RIGHT"

    -- Spacers for every loaded member, taking part or not: one that joins
    -- mid-combat then finds its spacer built.
    local seen = {}
    for _, m in ipairs(members) do
        local trackerId = m.trackerId
        local rec = s.records[trackerId]
        if not rec then
            rec = NewRecord(gentry, s)
            s.records[trackerId] = rec
        end
        seen[trackerId] = true
        m.rec = rec
        m.length = m.main + spacing

        local display, measure
        local ready = rec.display.slotReady and (not centered or rec.measure.slotReady)
        if not ready then
            m.source = "fixed"
        elseif m.source == "aura" then
            if DisplayBuilt(m.tracker, m.tentry) then
                display = EnsureAura(gentry, s, rec.display, m.tracker, m.tentry, trackerId, dirKey, m.length)
                if centered then
                    measure = EnsureAura(gentry, s, rec.measure, m.tracker, m.tentry, trackerId, "LEFT", m.length / 2)
                end
            end
        elseif m.source == "bool" then
            display = EnsureBar(gentry, rec.display, dirKey, m.length)
            if centered then
                measure = EnsureBar(gentry, rec.measure, "LEFT", m.length / 2)
            end
        end
        -- A centered member is measured and placed by the same state or by
        -- none: one spacer without the other would move the row off center.
        if centered and not (display and measure) then
            display, measure = nil, nil
        end

        if not (display and display.container) then ParkAura(rec.display) end
        if not (display and display.tex) then ParkBar(rec.display) end
        if not (measure and measure.container) then ParkAura(rec.measure) end
        if not (measure and measure.tex) then ParkBar(rec.measure) end

        m.spacers = { display = display, measure = measure }
        if display and display.tex then
            boolRecords[trackerId] = rec
            Slots.Feed(trackerId)
        else
            boolRecords[trackerId] = nil
        end

        -- A member the plain gates leave out keeps its joints on the frame.
        if not m.included then
            local near = DIRS[dirKey].near
            for _, role in ipairs(rec.roles) do
                role.joint:ClearAllPoints()
                role.joint:SetPoint(near, gentry.frame, near, 0, 0)
            end
        end
    end
    for trackerId, rec in pairs(s.records) do
        if not seen[trackerId] then ParkRecord(trackerId, rec) end
    end

    local frame = gentry.frame
    local ok, ref, point, x, y = true, frame, DIRS[dirKey].near, 0, 0
    if centered then
        ok, ref, point, x, y = RunChain(members, "measure", "LEFT", false, frame, "BOTTOM", 0, 0)
        -- Every open slot counts its spacing, so the measure runs half a
        -- spacing past the row's left end.
        if ok then x = x + spacing / 2 end
    end
    if ok then
        ok = RunChain(members, "display", dirKey, true, ref, point, x, y)
    end
    if not ok then
        -- The client refused an anchor onto the chain. The caller's plain
        -- chain re-anchors every visual, and the chain stays off.
        refused = "anchor refused"
        Engine._SetResult("slots", refused)
        ParkAll(gentry)
        return false
    end
    s.active = true
    return true
end

--------------------------------------------------------------------------------
-- Upkeep
--------------------------------------------------------------------------------

--- Whether any group's spacers wait on the structural gate.
function Slots.HasPendingWork()
    local Groups = SAU.Groups
    for _, gentry in pairs(Groups and Groups._byGroup or {}) do
        if gentry.slots and gentry.slots.pending then return true end
    end
    return false
end

--- Resyncs the spacer containers bound to a unit, or all of them: a target
-- or focus container does not refresh on a change of unit, and a container
-- hidden with its group has processed nothing since.
function Slots.KickUnit(unit)
    for a in pairs(auraSpacers) do
        if not a.parked and (unit == nil or a.unit == unit) then
            pcall(a.container.UpdateAllAuras, a.container)
        end
    end
end

function Slots.IsEnabled()
    return enabled
end

--- The session switch (debug command). Off lays every group out on its
-- plain chain at the next pass.
function Slots.SetEnabled(on)
    enabled = on and true or false
    if SAU.Groups then SAU.Groups.ReflowAll() end
end

--- Lines for the debug window: the switch, and each group's chain.
function Slots.AddDebug(push)
    push(("Slots: enabled=%s refused=%s pending=%s"):format(
        tostring(enabled), tostring(refused or false), tostring(Slots.HasPendingWork())))
    local Groups = SAU.Groups
    for gid, gentry in pairs(Groups and Groups._byGroup or {}) do
        local s = gentry.slots
        if s then
            push(("  g%s: active=%s pending=%s retired=%d"):format(
                tostring(gid), tostring(s.active or false), tostring(s.pending or false), s.retired))
            for trackerId, rec in pairs(s.records) do
                local parts = {}
                for index, role in ipairs(rec.roles) do
                    local name = index == 1 and "display" or "measure"
                    local a, b = role.aura, role.bar
                    if a then
                        parts[#parts + 1] = ("%s aura %s len=%s%s"):format(
                            name, a.dirKey, tostring(a.length), a.parked and " parked" or "")
                    end
                    if b and b.live then
                        parts[#parts + 1] = ("%s bar %s len=%s"):format(name, tostring(b.dirKey), tostring(b.length))
                    end
                end
                local tracker = SAU.GetTracker(trackerId)
                push(("    t%s source=%s %s"):format(tostring(trackerId),
                    tracker and SAU.SlotSource(tracker) or "gone",
                    #parts > 0 and table.concat(parts, "; ") or "no spacer"))
            end
        end
    end
end
