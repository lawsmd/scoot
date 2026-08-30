-- scootauras/missing.lua - Missing-buff trackers: the reminder that shows while
-- the player LACKS a buff
--
-- The engine cannot tell Lua that a slot is empty: the button's shown state is
-- a secret, the button tree is denied to addon Lua while auras are secret, and
-- no engine write ever calls back into Lua. For a permanent buff even the
-- duration object is blind, since Blizzard writes a zero span for any aura
-- without an expiration and for an empty slot alike
-- (Blizzard_AuraButton.lua UpdateAuraDuration).
--
-- What the engine does do is SIZE THE CONTAINER. A container that owns an aura
-- group runs Blizzard's flow layout on every aura update and ends the pass
-- with container:SetSize(secretwrap(width, height))
-- (Blizzard_CustomAuraContainer.lua CustomAuraContainerFlowLayoutMixin:
-- OnLayoutComplete; AnchorUtil.ApplyFlowLayout): 1 x 1 while the group has no
-- frame, elementWidth x elementHeight from the group's layout options while
-- it has one. Blizzard sanctions anchoring addon frames to that container (the
-- AddAuraGroup comment names DisableUntrustedLayoutScriptsTemplate for it).
-- So the reminder is pushed out of view by geometry the engine writes, never
-- by a Lua decision:
--
--   visual (Scoot, W x H from SetHostSize)
--    |- clip (Scoot, visual rect + margin, SetClipsChildren)     level visual+1
--    |   +- content (Scoot, W x H, icon + name text, blink;
--    |        DisableUntrustedLayoutScriptsTemplate)
--    |        anchored: content LEFT -> container RIGHT
--    +- container (engine, 1 x 1, LEFT at visual LEFT - 1)       level visual+5
--        +- aura group: maxFrameCount 1, elementWidth PUSH, elementHeight 1
--            +- gate frames (1 x 1, mouse off; nothing bound, nothing drawn)
--
-- Buff absent: the group has no frame, the layout sizes the container 1 x 1,
-- its right edge is the visual's left edge, content sits exactly in the clip
-- window and renders. Buff present: the group assigns a frame, the layout
-- sizes the container PUSH wide, content is pushed PUSH px to the right, out
-- of the window, and nothing renders.
--
-- Why not an engine-written FontString, which the first build used: a
-- region that is 0 wide or 0 high has no rect at all (Blizzard's
-- LayoutFrame.lua:487 says so; ApplyFlowLayout floors its sizes at 1 for the
-- same reason), and every engine text binding writes "" for an empty slot.
-- A chain anchored through such a FontString is undefined exactly while the
-- buff is missing, so the reminder never rendered. The layout's floor of 1
-- is what keeps this gate valid in both states.
--
-- On "My Group" the same reminder answers a second question: does anyone in the
-- party or raid lack the buff. That one is plain, so it moves the content
-- anchor instead of the geometry (see "Group signal" below): forced on, the
-- content sits on the visual and shows whatever the player's own state is.
--
-- "Only in Combat", the enable state and the blink drive clip/content from
-- plain state only. Everything here except the container is Scoot-owned, so
-- styling edits apply mid-combat.
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = SAU.Engine

local Missing = {}
SAU.Missing = Missing

-- Container width the layout writes while the buff is present. Far larger
-- than any host plus clip margins (hosts run well under 1000 px).
local PUSH = 4096
-- The template Blizzard names for frames anchored to a group-sized container
-- (Blizzard_SharedXMLBase/ForbiddenAspectTemplates.xml).
local CONTENT_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"
local BLINK_LOW_ALPHA = 0.15
local BLINK_SECONDS = 0.5
-- Shared with underlay.lua, so both reveal blinks run one cadence.
Missing.BLINK_LOW_ALPHA = BLINK_LOW_ALPHA
Missing.BLINK_SECONDS = BLINK_SECONDS
-- The clip window is the host rect plus this margin on every side, so icon
-- border art that draws outside the icon (up to 8 px) and pixel snapping
-- never slice the reminder while it sits in place. The present-state push
-- (PUSH px) still clears it entirely.
local CLIP_MARGIN = 12

--------------------------------------------------------------------------------
-- Scoot-owned visual (per pool entry, session-permanent)
--------------------------------------------------------------------------------

local function CreateContent(clip)
    -- The template carries the forbidden aspect the container demands of
    -- anything anchored to it. A client without the template still gets a
    -- frame; the anchor result then says what happened.
    local ok, frame = pcall(CreateFrame, "Frame", nil, clip, CONTENT_TEMPLATE)
    if ok and frame then return frame, true end
    return CreateFrame("Frame", nil, clip), false
end

local function EnsureVisual(entry)
    if entry.missing then return entry.missing end
    local visual = entry.visual

    local clip = CreateFrame("Frame", nil, visual)
    clip:SetPoint("TOPLEFT", visual, "TOPLEFT", -CLIP_MARGIN, CLIP_MARGIN)
    clip:SetPoint("BOTTOMRIGHT", visual, "BOTTOMRIGHT", CLIP_MARGIN, -CLIP_MARGIN)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(visual:GetFrameLevel() + 1)
    clip:Hide()

    local content, templated = CreateContent(clip)
    content:SetSize(32, 32)
    content:SetFrameLevel(clip:GetFrameLevel() + 1)
    -- Unanchored until a gate container exists to anchor to (OnBuilt).
    content:Hide()

    local set = Engine.BuildElementSet(content)

    local blink = content:CreateAnimationGroup()
    blink:SetLooping("BOUNCE")
    local alpha = blink:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(BLINK_LOW_ALPHA)
    alpha:SetDuration(BLINK_SECONDS)

    entry.missing = {
        clip = clip,
        content = content,
        templated = templated,
        elements = set.elements,
        textFrame = set.textFrame,
        blink = blink,
        wired = false,
    }
    return entry.missing
end

-- Text ruler per entry, on the visual (plain anchoring). The reminder's own
-- FontString cannot be measured once the content hangs off the engine-sized
-- container: string metrics are SecretWhenAnchoringSecret. A private ruler
-- also keeps one font per tracker, so a settled read is one frame away at
-- most (fonts.lua ruler notes).
local function EnsureRuler(entry)
    local m = EnsureVisual(entry)
    if m.ruler then return m.ruler end
    local holder = CreateFrame("Frame", nil, entry.visual)
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER", entry.visual, "CENTER", 0, 0)
    holder:Hide()
    local fs = holder:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", holder, "CENTER", 0, 0)
    addon.ApplyFontStyle(fs, addon.ResolveFontFace("FRIZQT__"), 12, "")
    fs:SetWidth(0)
    fs:SetWordWrap(false)
    fs:SetTextScale(1)
    m.ruler = fs
    return fs
end

--- Natural width and height of the reminder text in the tracker's name font.
-- Called by the layout pass (layout.lua, vis.missing branch). Returns numbers
-- only; nil height when the ruler could not say.
function Missing.MeasureText(entry, text, db)
    local face = addon.ResolveFontFace(db and db.nameTextFont)
    local size = tonumber(db and db.nameTextSize) or 14
    local style = (db and db.nameTextStyle) or "OUTLINE"
    local ruler = entry and EnsureRuler(entry) or nil
    if ruler then
        addon.ApplyFontStyle(ruler, face, size, style)
        ruler:SetText(text or "")
        local ok, w = pcall(ruler.GetUnboundedStringWidth, ruler)
        local ok2, h = pcall(ruler.GetStringHeight, ruler)
        local width = (ok and type(w) == "number" and not issecretvalue(w)) and w or nil
        local height = (ok2 and type(h) == "number" and not issecretvalue(h)) and h or nil
        if width then return width, height end
    end
    local w = addon.MeasureTextWidth and addon.MeasureTextWidth(text or "", face, size, style)
    return w or 0, nil
end

--------------------------------------------------------------------------------
-- The gate: container placement, aura group, content anchor
--------------------------------------------------------------------------------

--- Places a fresh gate container: LEFT edge one pixel left of the visual's
-- LEFT edge, so the layout's empty-group size (1 x 1) puts its RIGHT edge on
-- the visual's left edge. It starts PUSH wide (reminder out of view) and the
-- first layout pass corrects it: closed until the engine says otherwise.
-- Called by EnsureBuilt instead of the centered 32 x 32 placement regular
-- kinds use.
function Missing.PlaceContainer(entry, container)
    pcall(container.SetSize, container, PUSH, 1)
    pcall(container.SetPoint, container, "LEFT", entry.visual, "LEFT", -1, 0)
end

-- Group frames exist only to be counted by the layout. The layout reads
-- elementWidth/elementHeight from the group options, never the frame, so the
-- frame can be a mouse-dead point.
local function InitGateFrame(button)
    pcall(button.SetSize, button, 1, 1)
    pcall(button.EnableMouse, button, false)
    pcall(button.SetMouseClickEnabled, button, false)
    pcall(button.SetMouseMotionEnabled, button, false)
end

--- Anchors the reminder content and shows it. Two positions, both Scoot-owned
-- frame ops and so legal in combat: forced, it sits on the visual and renders
-- whatever the player's own buff state is; otherwise it hangs off the gate
-- container's right edge, where the engine's own sizing decides whether it
-- lands inside the clip window. No container and not forced means nothing to
-- anchor to, so it hides until the next build.
function Missing.ApplyContentAnchor(entry, trackerId)
    local m = entry and entry.missing
    if not m then return end
    trackerId = trackerId or entry.occupantId
    m.content:ClearAllPoints()

    local ok, err, how
    if m.forced then
        ok, err = pcall(m.content.SetPoint, m.content, "LEFT", entry.visual, "LEFT", 0, 0)
        how = "anchored (group)"
    elseif m.container then
        ok, err = pcall(m.content.SetPoint, m.content, "LEFT", m.container, "RIGHT", 0, 0)
        how = m.templated and "anchored" or "anchored (plain frame; template missing)"
    else
        m.content:Hide()
        m.wired = false
        if trackerId then Engine._SetResult("gate.t" .. trackerId, "no container") end
        return
    end

    if ok then
        m.content:Show()
        m.wired = true
    else
        m.content:Hide()
        m.wired = false
        how = "anchor FAILED: " .. tostring(err)
    end
    if trackerId then Engine._SetResult("gate.t" .. trackerId, how) end
end

--- Adds the gate group to a fresh container and anchors the content past it.
-- Caller holds the structural gate (EnsureBuilt). Returns ok, err.
function Missing.AddGateGroup(trackerId, tracker, entry, container, candidateFilters)
    local groupKey = "scootMissing" .. trackerId .. "_" .. (entry.slotSeq or 0)
    local ok, err = pcall(container.AddAuraGroup, container, groupKey, SAU.FilterForKind(tracker.kind), {
        candidateFilters = candidateFilters,
        maxFrameCount = 1,
        layout = { elementWidth = PUSH, elementHeight = 1 },
        initializeFrame = InitGateFrame,
    })
    if not ok then return false, err end
    entry.gateGroupKey = groupKey
    Missing.OnBuilt(trackerId, entry, container)
    return true
end

--- Records the fresh container and anchors to it. Runs once per fresh
-- container; a revived container keeps its anchor.
function Missing.OnBuilt(trackerId, entry, container)
    local m = EnsureVisual(entry)
    m.container = container
    Missing.ApplyContentAnchor(entry, trackerId)
end

--- The container that gated the content is being retired; the content anchor
-- now points at a parked frame. A forced reminder moves to the visual and
-- keeps showing, everything else hides until the next build re-anchors.
function Missing.OnRetire(entry)
    entry.gateGroupKey = nil
    local m = entry.missing
    if not m then return end
    m.container = nil
    Missing.ApplyContentAnchor(entry)
end

-- The container is NOT cleared here: a released entry keeps it parked, and
-- EnsureBuilt revives that entry whole when the next occupant's content
-- matches, without ever calling OnBuilt again. Only the forced state resets,
-- so the anchor goes back to the container it still has.
function Missing.OnEntryReleased(entry)
    local m = entry.missing
    if not m then return end
    m.clip:Hide()
    if m.forced then
        m.forced = false
        Missing.ApplyContentAnchor(entry)
    end
    if m.blink:IsPlaying() then m.blink:Stop() end
    m.content:SetAlpha(1)
    Missing.SyncTickers()
end

--------------------------------------------------------------------------------
-- Text, styling, layout (Tier 1: Scoot frames only)
--------------------------------------------------------------------------------

--- The reminder text: the aura's name as the player knows the spell, with the
-- optional suffix.
function Missing.ReminderText(tracker, db)
    local name = SAU.DescribeSpell(tracker.spellId)
    if db and db.missingSuffix == true then
        return name .. " missing!"
    end
    return name
end

--- Paints one Scoot-owned element set (the live content or the Edit Mode
-- preview) as the reminder: text, then the shared styling/layout chain, then
-- everything the reminder never shows hidden. `shim` is the chain's state
-- table for that set ({ container, elements, entry }); the reminder text is
-- stashed on it for the layout's ruler measurement.
function Missing.PaintElementSet(trackerId, tracker, shim, elements)
    local db = SAU.GetDB(trackerId)
    local vis = SAU.ResolveVisibility(tracker, db)
    local text = Missing.ReminderText(tracker, db)
    shim.reminderText = text

    local nameFS
    for _, elem in ipairs(elements or {}) do
        if elem.type == "text" and elem.def.source == "name" then
            nameFS = elem.widget
        end
    end
    if nameFS then
        nameFS:SetText(text)
    end

    SAU._ApplyIconMode(trackerId, tracker, shim)
    SAU._ApplyShapeStyling(trackerId, tracker, shim)
    SAU._ApplyBorders(trackerId, tracker, shim)
    SAU._ApplyTextStyling(trackerId, tracker, shim)
    SAU._LayoutElements(trackerId, tracker, shim)

    for _, elem in ipairs(elements or {}) do
        if elem.type == "texture" then
            if not vis.showIcon and elem.borderFrame then
                elem.borderFrame:Hide()
            end
        elseif elem.type == "text" then
            if elem.def.source ~= "name" then elem.widget:Hide() end
        elseif elem.type == "bar" then
            elem.widget:Hide()
        elseif elem.type == "cooldown" then
            pcall(elem.widget.Clear, elem.widget)
            elem.widget:Hide()
        end
    end
end

local function PaintLive(trackerId, tracker, entry, m)
    local shim = { container = m.content, elements = m.elements, entry = entry }
    Missing.PaintElementSet(trackerId, tracker, shim, m.elements)
    m.content:SetSize(math.max(entry.hostW or 32, 1), math.max(entry.hostH or 32, 1))
    Missing.UpdateGate(trackerId)
end

--- Full Tier 1 pass for one live tracker: build the visual on first use,
-- paint it, size the content to the host, and apply the plain-state gate.
function Missing.Restyle(trackerId, tracker, state)
    local entry = state and state.entry
    if not entry then return end
    local m = EnsureVisual(entry)
    PaintLive(trackerId, tracker, entry, m)
    -- A tracker may have just become (or stopped being) a group tracker, or be
    -- the first reminder either poll needs to run for.
    Missing.SyncTickers()
    -- Text metrics settle a frame after a font change; one deferred repaint
    -- picks up the settled width so the host, and with it the clip window,
    -- is never left a frame stale.
    if not m.repaintPending then
        m.repaintPending = true
        C_Timer.After(0, function()
            m.repaintPending = false
            local live = SAU.GetTracker(trackerId)
            local st = SAU._activeStates[trackerId]
            if live and live.kind == "missingbuff" and st and st.entry == entry then
                PaintLive(trackerId, live, entry, m)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Group signal: does anyone in the party or raid lack the buff
--
-- The container gate answers for the player and nothing else, and forty secret
-- widths cannot be combined in Lua. What can be read is the buff itself:
-- C_UnitAuras.GetUnitAuraBySpellID is RequiresNonSecretAura, so it returns
-- nothing instead of throwing under restriction, and it hands back real data
-- for a spell the engine flags NeverSecret. Raid buffs are that class
-- (Blizzard_AuraContainerUtil.lua exempts NeverSecret spells from every
-- identity restriction), so the roster scan is plain, exact, and legal in
-- combat. Anything else falls back to the action button glow, which is also
-- plain (SpellActivationOverlayDocumentation.lua carries no secrecy
-- annotation) but whose firing rule lives in the engine, where no source can
-- confirm it.
--
-- Both providers return a plain boolean, so the caller may branch on it. The
-- verdict only ever forces the reminder ON; the player's own half stays with
-- the container geometry.
--------------------------------------------------------------------------------

local GROUP_POLL_SECONDS = 1
local GLOW_LOG_SIZE = 20
-- Yards, and the square the distance read is compared against. Group-wide
-- buffs name this radius in their own tooltips ("all party and raid members
-- within 100 yards"), so a member inside it is one the player's cast would
-- reach. Only used when the tracked spell carries no range of its own, which
-- every self-cast raid buff is.
local GROUP_RANGE_YARDS = 100
local GROUP_RANGE_SQUARED = GROUP_RANGE_YARDS * GROUP_RANGE_YARDS

local glowLog = {}
local glowNext = 1
local groupTicker = nil

--- Plain read of a one-argument predicate: true, false, or nil when the call
-- failed or came back secret. nil fails every comparison below, so an
-- unreadable unit is skipped rather than guessed at.
local function Plain(fn, arg)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, arg)
    if not ok then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v and true or false
end

--- Ids the tracked spell can appear under: talent overrides, rank variants and
-- tooltip proxies all carry their own. Cached per tracker, and rebuilt when the
-- spell changes or when the Cooldown Manager catalog behind the expansion does.
-- The epoch is the shared one AuraIds keeps, so this record and the expansion
-- it was built from cannot drift; a set built before COOLDOWN_VIEWER_DATA_LOADED
-- used to hold the bare spell id forever, taking the memoised range and
-- provider verdicts on the same record down with it.
local idSets = {}

local function IdSet(trackerId, tracker)
    local version = addon.AuraIds.GetVersion and addon.AuraIds.GetVersion() or 0
    local set = idSets[trackerId]
    if set and set.spellId == tracker.spellId and set.version == version then
        return set
    end
    local ids = {}
    local ok, include = pcall(addon.AuraIds.BuildIncludeSet, tracker.spellId)
    if ok and type(include) == "table" then
        for id in pairs(include) do table.insert(ids, id) end
    end
    if #ids == 0 then ids[1] = tracker.spellId end
    table.sort(ids)
    set = { spellId = tracker.spellId, ids = ids, version = version }
    idSets[trackerId] = set
    return set
end

local function IsNeverSecret(spellId)
    local fn = C_Secrets and C_Secrets.GetSpellAuraSecrecy
    local never = Enum and Enum.SecrecyLevel and Enum.SecrecyLevel.NeverSecret
    if type(fn) ~= "function" or never == nil then return false end
    local ok, level = pcall(fn, spellId)
    if not ok then return false end
    if issecretvalue and issecretvalue(level) then return false end
    return level == never
end

--- The first id in the set whose spell carries a real range AND can be cast on
-- a friendly target, or nil when none does. A targeted buff (Earth Shield and
-- its like) qualifies and the engine can then answer the range question
-- exactly; a self-cast raid buff carries no range, so the distance test stands
-- in. The helpful test matters: an include set can hold a harmful id with a
-- range of its own, and asking that spell about a friendly unit answers false
-- for every group member, which would hold the whole scan shut. Resolved once
-- per id set, and so re-resolved whenever the tracked spell changes.
local function RangeSpellId(set)
    if set.rangeId == nil then
        set.rangeId = false
        local hasRange = C_Spell and C_Spell.SpellHasRange
        local isHelpful = C_Spell and C_Spell.IsSpellHelpful
        if type(hasRange) == "function" and type(isHelpful) == "function" then
            for _, id in ipairs(set.ids) do
                local rok, ranged = pcall(hasRange, id)
                local hok, helpful = pcall(isHelpful, id)
                if rok and hok
                    and not (issecretvalue and (issecretvalue(ranged) or issecretvalue(helpful)))
                    and ranged == true and helpful == true then
                    set.rangeId = id
                    break
                end
            end
        end
    end
    return set.rangeId or nil
end

--- "scan" when the engine hands plain aura data for this spell on other units,
-- "glow" otherwise. Resolved once per id set.
function Missing.Provider(trackerId, tracker)
    local set = IdSet(trackerId, tracker)
    if set.scannable == nil then
        set.scannable = false
        for _, id in ipairs(set.ids) do
            if IsNeverSecret(id) then
                set.scannable = true
                break
            end
        end
    end
    return set.scannable and "scan" or "glow"
end

--- The ids the group signal watches for this tracker, for the debug window.
function Missing.SpellIds(trackerId, tracker)
    return IdSet(trackerId, tracker).ids
end

--- The player plus every group member, as plain unit tokens. IsInRaid,
-- IsInGroup and GetNumGroupMembers carry no secrecy restriction. In a raid the
-- raid tokens already include the player.
local groupUnits = {}

local function GroupUnits()
    wipe(groupUnits)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do groupUnits[#groupUnits + 1] = "raid" .. i end
    else
        groupUnits[1] = "player"
        for i = 1, GetNumGroupMembers() - 1 do groupUnits[#groupUnits + 1] = "party" .. i end
    end
    return groupUnits
end

--- Whether the buff could reach this unit from where the player stands. Two
-- plain reads, the more precise one first:
--   C_Spell.IsSpellInRange   the spell's own answer (no SecretReturns in
--                            SpellDocumentation.lua); nil for a spell with no
--                            range, which every self-cast raid buff is
--   UnitDistanceSquared      distance and checkedDistance, both plain
--                            (UnitDocumentation.lua); checkedDistance is false
--                            for a unit the client cannot place, which is the
--                            other zone this gate was added for
-- UnitInRange, the obvious call, carries SecretReturns = true and cannot be
-- branched on from addon context at all. Neither read answering means the unit
-- is skipped, the same fail-closed rule the other gates follow. The second
-- return names the verdict for the debug table: a string, or the squared
-- distance, which only the report turns into yards.
local function InGroupRange(unit, rangeId)
    if rangeId then
        local ok, inRange = pcall(C_Spell.IsSpellInRange, rangeId, unit)
        if ok and type(inRange) == "boolean" and not (issecretvalue and issecretvalue(inRange)) then
            return inRange, inRange and "in spell range" or "out of spell range"
        end
    end
    local ok, dist, checked = pcall(UnitDistanceSquared, unit)
    if ok and type(dist) == "number"
        and not (issecretvalue and issecretvalue(dist))
        and not (issecretvalue and issecretvalue(checked))
        and checked == true then
        return dist <= GROUP_RANGE_SQUARED, dist
    end
    return false, "unplaceable"
end

--- Whether a unit's answer counts, and when it does not, which test refused
-- it. A unit we cannot see is skipped, never counted as missing:
-- GetUnitAuraBySpellID returns nil for a unit that is not visible (its own
-- documentation says so), so counting them would pin the reminder on for any
-- raid spread across a room. UnitInRange is the tighter test and is
-- SecretReturns in instances, which is why UnitIsVisible stands in here, the
-- same substitution Blizzard's raid frames make. Visibility alone is too
-- loose: members in another zone passed it and were counted missing, so
-- InGroupRange has the last word.
local function UnitCounts(unit, rangeId)
    if Plain(UnitExists, unit) ~= true then return false, "absent" end
    -- Party slots hold real players and, in follower dungeons and walk-in
    -- parties, AI companions. Both take group buffs, and neither is a pet:
    -- pets ride partypet and raidpet tokens and never reach this list.
    -- Blizzard pairs the same tests in its own frames for exactly these units
    -- (CompactUnitFrame.lua:672 and :859, UnitFrame.lua:155).
    if Plain(UnitIsPlayer, unit) ~= true
        and Plain(UnitInPartyIsAI, unit) ~= true
        and Plain(UnitTreatAsPlayerForDisplay, unit) ~= true then
        return false, "not a player"
    end
    if Plain(UnitIsConnected, unit) ~= true then return false, "offline" end
    if Plain(UnitIsVisible, unit) ~= true then return false, "not visible" end
    if Plain(UnitIsDeadOrGhost, unit) ~= false then return false, "dead" end
    local inRange, detail = InGroupRange(unit, rangeId)
    if not inRange then return false, detail end
    return true, detail
end

local function UnitCarriesId(fn, unit, id)
    local ok, aura = pcall(fn, unit, id)
    return ok and aura ~= nil and not (issecretvalue and issecretvalue(aura))
end

--- True when the unit plainly carries one of the ids. A nil return is "no aura
-- here", which is what the scan wants; the getter never throws. `extraId` is
-- the substituted spell the include set does not hold (see ScanGroup).
local function UnitHasAura(unit, ids, extraId)
    local fn = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if type(fn) ~= "function" then return false end
    for _, id in ipairs(ids) do
        if UnitCarriesId(fn, unit, id) then return true end
    end
    return extraId ~= nil and UnitCarriesId(fn, unit, extraId) or false
end

--- True when at least one counted unit lacks every id. `report`, when given,
-- collects the per-unit verdicts for the debug window and turns off the early
-- exit. `escaping` is the spell the game has substituted for the tracked one:
-- this scan reads the player's own row (GroupUnits leads with "player" solo,
-- and raid tokens include them), so without it a form swap counts the player
-- as missing and forces the reminder on for the whole window.
local function ScanGroup(set, report, escaping)
    local ids = set.ids
    local rangeId = RangeSpellId(set)
    local missing = false
    for _, unit in ipairs(GroupUnits()) do
        local counts, why = UnitCounts(unit, rangeId)
        local has = counts and UnitHasAura(unit, ids, escaping) or false
        if report then
            if type(why) == "number" then why = string.format("%.0f yd", math.sqrt(why)) end
            table.insert(report, { unit = unit, counted = counts, why = why, has = has })
        end
        if counts and not has then
            missing = true
            if not report then break end
        end
    end
    return missing
end

--- True when the game is glowing an action button for any of the ids. The
-- engine decides what that means; Scoot only mirrors it.
local function GlowActive(ids)
    local fn = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
    if type(fn) ~= "function" then return false end
    for _, id in ipairs(ids) do
        local ok, on = pcall(fn, id)
        if ok and not (issecretvalue and issecretvalue(on)) and on == true then
            return true
        end
    end
    return false
end

--- The group verdict for one tracker. False for anything that is not a group
-- missing-buff tracker, so callers need no other guard.
function Missing.GroupSignalActive(trackerId, tracker, report)
    if not tracker or tracker.kind ~= "missingbuff" or tracker.unit ~= "group" then
        return false
    end
    local set = IdSet(trackerId, tracker)
    if Missing.Provider(trackerId, tracker) == "scan" then
        return ScanGroup(set, report, SAU.EscapingOverrideFor(tracker.spellId))
    end
    return GlowActive(set.ids)
end

--- The last GLOW_LOG_SIZE glow events, oldest first, for the debug window.
function Missing.GlowLog()
    local out = {}
    for i = 0, GLOW_LOG_SIZE - 1 do
        local rec = glowLog[((glowNext - 1 + i) % GLOW_LOG_SIZE) + 1]
        if rec then table.insert(out, rec) end
    end
    return out
end

--- SPELL_ACTIVATION_OVERLAY_GLOW_SHOW and _HIDE. The payload id is plain and
-- is often an override of the one the user picked, so nothing is matched here:
-- the log is for the debug window and the refresh re-polls the trackers that
-- read the glow. Only those: this fires on every proc in the game, and a
-- scanning tracker would pay a roster walk for each one.
function Missing.OnOverlayGlow(spellID, shown)
    if type(spellID) == "number" and not (issecretvalue and issecretvalue(spellID)) then
        glowLog[glowNext] = { shown = shown and true or false, id = spellID }
        glowNext = (glowNext % GLOW_LOG_SIZE) + 1
    end
    Missing.RefreshGroupTrackers("glow")
end

local function AnyGroupTrackerLive()
    for trackerId in pairs(SAU._activeStates) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and tracker.kind == "missingbuff" and tracker.unit == "group" then
            return true
        end
    end
    return false
end

--- Starts or stops the poll to match the live group trackers.
function Missing.SyncGroupTicker()
    if AnyGroupTrackerLive() then
        if not groupTicker then
            groupTicker = C_Timer.NewTicker(GROUP_POLL_SECONDS, function()
                Missing.RefreshGroupTrackers()
            end)
        end
    elseif groupTicker then
        groupTicker:Cancel()
        groupTicker = nil
    end
end

--- One pass over the live group trackers: the poll's callback, and the handler
-- for the roster and glow events. `providerOnly`, when given, limits the pass
-- to trackers that read that provider. A group member losing a buff fires
-- UNIT_AURA on their own frame, which is secret in restricted content, so a
-- slow poll is the only honest signal there is.
function Missing.RefreshGroupTrackers(providerOnly)
    for trackerId in pairs(SAU._activeStates) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and tracker.kind == "missingbuff" and tracker.unit == "group"
            and (providerOnly == nil or Missing.Provider(trackerId, tracker) == providerOnly) then
            Missing.UpdateGate(trackerId)
        end
    end
    Missing.SyncTickers()
end

--------------------------------------------------------------------------------
-- Substituted spells: noticing a form swap
--
-- C_Spell.GetOverrideSpell carries no event of its own, and most forms and
-- stances are not Cooldown Manager entries, so the CDM override event does not
-- cover them either. The events are the fast path and this poll is the
-- guarantee. It stays deliberately thin: one C call per DISTINCT live tracked
-- spell, and no downstream work at all unless an answer moved. It must never
-- call SAU.DisplaySpellFor (which walks the whole catalog while that catalog is
-- still empty) or the group signal (a walk of up to forty units, and the group
-- ticker's job at a quarter the rate).
--------------------------------------------------------------------------------

local OVERRIDE_POLL_SECONDS = 0.25
local overrideTicker = nil
local overrideSeen = {}
local liveSpellIds = {}
local overrideChanged = {}

--- The distinct spell ids the live reminders watch. Reused table.
local function LiveMissingSpellIds()
    wipe(liveSpellIds)
    for trackerId in pairs(SAU._activeStates) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and tracker.kind == "missingbuff" and type(tracker.spellId) == "number" then
            liveSpellIds[tracker.spellId] = true
        end
    end
    return liveSpellIds
end

--- Repaints and re-gates the reminders watching one spell, or every reminder
-- when none is named. Restyle is Tier 1 (Scoot frames only), so it is legal
-- mid-combat, which is where every form swap happens.
function Missing.RefreshOverrideDependents(spellId)
    for trackerId, state in pairs(SAU._activeStates) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and tracker.kind == "missingbuff"
            and (spellId == nil or tracker.spellId == spellId) then
            Missing.Restyle(trackerId, tracker, state)
        end
    end
end

-- Collect first, dispatch second: the refresh re-enters enough of this file
-- that iterating the reused table across it would be a trap. Returns whether
-- anything was dispatched.
local function PollOverrides(forceSpellId)
    wipe(overrideChanged)
    for spellId in pairs(LiveMissingSpellIds()) do
        local ok, id = pcall(C_Spell.GetOverrideSpell, spellId)
        id = (ok and type(id) == "number"
            and not (issecretvalue and issecretvalue(id))) and id or spellId
        if overrideSeen[spellId] ~= id or spellId == forceSpellId then
            overrideSeen[spellId] = id
            table.insert(overrideChanged, spellId)
        end
    end
    for _, spellId in ipairs(overrideChanged) do
        Missing.RefreshOverrideDependents(spellId)
    end
    return #overrideChanged > 0
end

--- COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED, and the coalesced pass behind
-- UPDATE_SHAPESHIFT_FORM and SPELLS_CHANGED. `baseSpellID`, when the payload
-- carries one, is refreshed even if GetOverrideSpell did not move: the map
-- behind DisplaySpellFor can shift on its own.
function Missing.OnOverrideChanged(baseSpellID)
    local id = (type(baseSpellID) == "number"
        and not (issecretvalue and issecretvalue(baseSpellID))) and baseSpellID or nil
    -- A tracker may store a tooltip-override or a linked id rather than the
    -- base the event names, so a payload matching nothing live is no proof
    -- that nothing moved. Repaint every reminder in that case: one Tier 1 pass
    -- over a handful of frames, and only when the game reports a substitution.
    if not PollOverrides(id) then
        Missing.RefreshOverrideDependents()
    end
end

--- Whether any reminder is live at all. The events feeding the override poll
-- are noisy and fire on the shared frame for every user, so they read this
-- before doing anything.
function Missing.AnyLive()
    for trackerId in pairs(SAU._activeStates) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and tracker.kind == "missingbuff" then return true end
    end
    return false
end

--- Starts or stops the override poll to match the live reminders.
function Missing.SyncOverrideTicker()
    if Missing.AnyLive() then
        if not overrideTicker then
            overrideTicker = C_Timer.NewTicker(OVERRIDE_POLL_SECONDS, function()
                PollOverrides()
            end)
        end
    elseif overrideTicker then
        overrideTicker:Cancel()
        overrideTicker = nil
        wipe(overrideSeen)
    end
end

--- Both polls, synced together. Every site that used to call SyncGroupTicker
-- calls this instead, so neither can be missed.
function Missing.SyncTickers()
    Missing.SyncGroupTicker()
    Missing.SyncOverrideTicker()
end

--------------------------------------------------------------------------------
-- Plain-state gate: enable, Only in Combat, Only in Instances, Edit Mode, blink
--------------------------------------------------------------------------------

-- Housing interiors and neighbourhoods are instanced but are not content, and
-- Blizzard excludes both ahead of its own generic test (Blizzard_FrameXML/
-- InstanceDifficulty.lua:101). Everything else IsInInstance reports is content:
-- dungeons, raids, battlegrounds, arenas, and scenarios, which is what a delve
-- runs as. Delves have reported as instances since 12.0.5.
local NON_CONTENT_INSTANCES = { none = true, interior = true, neighborhood = true }

--- Whether the player is inside instanced content. Plain throughout, so it may
-- be branched on freely.
local function PlayerInInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok then return false end
    return inInstance == true and not NON_CONTENT_INSTANCES[instanceType or "none"]
end

--- Shows or hides the clip window from plain state only, then re-evaluates
-- the group signal. The player's own presence is never consulted: the engine
-- handles that by geometry. Safe for any tracker id; a non-missing occupant of
-- an entry that once hosted a reminder hides it.
function Missing.UpdateGate(trackerId)
    local state = SAU._activeStates[trackerId]
    local entry = state and state.entry
    local m = entry and entry.missing
    if not m then return end

    local tracker = SAU.GetTracker(trackerId)
    local db = SAU.GetDB(trackerId)
    local show = tracker ~= nil
        and tracker.kind == "missingbuff"
        and SAU.IsTrackerActive(trackerId, tracker)
        and SAU.IsModuleActive()
    if show and tracker.onlyInCombat ~= false and not InCombatLockdown() then
        show = false
    end
    -- Reads `== true`, not `~= false`: this gate defaults OFF, so a tracker that
    -- predates the field (nil) keeps showing everywhere, as it always has.
    if show and tracker.onlyInInstances == true and not PlayerInInstance() then
        show = false
    end
    if show and SAU._isEditModeActive and SAU._isEditModeActive() then
        -- The Edit Mode preview stands in for the live reminder.
        show = false
    end

    -- The player's own half, and nothing else. The container answers "does the
    -- player have it" by geometry, but its candidate filter matches exact ids:
    -- a spell the game has substituted is invisible to it, so the aura group
    -- stays empty, the container stays 1 x 1, and the geometry reads "missing"
    -- for a buff the player plainly has. Hide it here instead. `show` itself
    -- stays untouched: it is the permission gate and it governs both halves.
    local escaping = show and tracker and SAU.EscapingOverrideFor(tracker.spellId) or nil

    -- The group half. Plain throughout, so it may be branched on, and it only
    -- ever forces the reminder on: the anchor moves, the clip and the blink
    -- stay on plain state. Derived from the permission gate, never from the
    -- self half above.
    local forced = show and Missing.GroupSignalActive(trackerId, tracker) or false
    if m.forced ~= forced then
        m.forced = forced
        Missing.ApplyContentAnchor(entry, trackerId)
    end

    -- Forced wins: the group's verdict is a separate question and outranks the
    -- player's own satisfied state, exactly as it outranks the container.
    local lit = show and (forced or not escaping) or false
    m.clip:SetShown(lit)

    if Engine._SetResult then
        Engine._SetResult("gatereason.t" .. trackerId,
            (not show and "gated off")
            or (escaping and not forced and ("override " .. tostring(escaping)))
            or (forced and "group forced")
            or "container")
    end

    local wantBlink = lit and db ~= nil and db.blinkWhenShown == true
    if wantBlink then
        if not m.blink:IsPlaying() then m.blink:Play() end
    else
        if m.blink:IsPlaying() then m.blink:Stop() end
        m.content:SetAlpha(1)
    end
end

--- Regen and zone events: re-evaluate every live reminder's gate.
function Missing.RefreshGates()
    for trackerId in pairs(SAU._activeStates) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and tracker.kind == "missingbuff" then
            Missing.UpdateGate(trackerId)
        end
    end
    Missing.SyncTickers()
end

--------------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------------

local SECRECY_NAMES = {}
if Enum and Enum.SecrecyLevel then
    for name, value in pairs(Enum.SecrecyLevel) do
        if type(value) == "number" then SECRECY_NAMES[value] = name end
    end
end

local function Describe(v)
    if issecretvalue and issecretvalue(v) then return "secret" end
    if type(v) == "table" then return "table" end
    return tostring(v)
end

-- Never index SECRECY_NAMES with the raw return: a secret table key throws.
local function SecrecyName(level)
    if issecretvalue and issecretvalue(level) then return "secret" end
    return SECRECY_NAMES[level] or tostring(level)
end

--- The group half, for /scoot debug sa missing <id>: which provider answers,
-- what every id says, and the per-unit scan table. Everything here is a fresh
-- read, so the window is the live state rather than a cache of it.
function Missing.AddGroupDebug(add, trackerId, tracker)
    local provider = Missing.Provider(trackerId, tracker)
    local state = SAU._activeStates[trackerId]
    local m = state and state.entry and state.entry.missing
    add("")
    add("--- group signal ---")
    add("provider=%s forced=%s inGroup=%s inRaid=%s members=%s",
        provider, tostring(m and m.forced), tostring(IsInGroup()), tostring(IsInRaid()),
        tostring(GetNumGroupMembers()))

    local ids = Missing.SpellIds(trackerId, tracker)
    for _, id in ipairs(ids) do
        local nok, level = pcall(function()
            return C_Secrets and C_Secrets.GetSpellAuraSecrecy and C_Secrets.GetSpellAuraSecrecy(id)
        end)
        local gok, glow = pcall(function()
            return C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
                and C_SpellActivationOverlay.IsSpellOverlayed(id)
        end)
        add("  id %-7d secrecy=%s IsSpellOverlayed=%s", id,
            nok and SecrecyName(level) or "error", gok and Describe(glow) or "error")
    end

    if provider == "scan" then
        local rangeId = RangeSpellId(IdSet(trackerId, tracker))
        add("range gate: %s", rangeId and ("IsSpellInRange on spell " .. rangeId)
            or (GROUP_RANGE_YARDS .. " yd (no tracked spell carries a range)"))
        local report = {}
        local verdict = Missing.GroupSignalActive(trackerId, tracker, report)
        add("scan verdict=%s over %d unit(s)", tostring(verdict), #report)
        for _, row in ipairs(report) do
            add("  %-7s counted=%-5s hasBuff=%-5s %s", row.unit, tostring(row.counted),
                tostring(row.has), row.why or "")
        end
    end

    local log = Missing.GlowLog()
    add("glow log%s", (#log == 0) and ": (empty)" or (" (" .. #log .. "):"))
    for _, rec in ipairs(log) do
        add("  %-4s %d", rec.shown and "SHOW" or "HIDE", rec.id)
    end
end

--- Lines for /scoot debug sa missing <id>.
function Missing.DebugInfo(trackerId)
    local lines = {}
    local function add(fmt, ...) table.insert(lines, string.format(fmt, ...)) end

    local tracker = SAU.GetTracker(trackerId)
    if not tracker then
        add("t%s: no such tracker", tostring(trackerId))
        return lines
    end
    local db = SAU.GetDB(trackerId)
    add("t%d spell=%d kind=%s shape=%s onlyInCombat=%s onlyInInstances=%s enabled=%s",
        trackerId, tracker.spellId, tostring(tracker.kind), tostring(tracker.shape),
        tostring(tracker.onlyInCombat), tostring(tracker.onlyInInstances),
        tostring(tracker.enabled))
    add("unit=%s engine=%s", tostring(tracker.unit), tostring(SAU.EngineUnitFor(tracker)))
    add("text=%q suffix=%s blink=%s anchor=%s",
        Missing.ReminderText(tracker, db), tostring(db and db.missingSuffix),
        tostring(db and db.blinkWhenShown), tostring(db and db.nameTextOuterAnchor))
    add("specs=%s specAllows=%s currentSpec=%s active=%s",
        SAU.DescribeSpecs(tracker.specs) or "all", tostring(SAU.SpecAllows(tracker)),
        tostring(SAU.CurrentSpecID()), tostring(SAU.IsTrackerActive(trackerId, tracker)))
    add("InCombatLockdown=%s AurasSecretNow=%s editMode=%s",
        tostring(InCombatLockdown()), tostring(addon.AurasSecretNow and addon.AurasSecretNow()),
        tostring(SAU._isEditModeActive and SAU._isEditModeActive()))
    -- The raw instanceType matters: without it a housing interior and a delve
    -- that failed to register both read as a bare "false".
    local iok, _, instanceType = pcall(IsInInstance)
    add("inInstance=%s instanceType=%s", tostring(PlayerInInstance()),
        iok and tostring(instanceType) or "error")

    local sok, secrecy = pcall(function()
        return C_Secrets and C_Secrets.GetSpellAuraSecrecy and C_Secrets.GetSpellAuraSecrecy(tracker.spellId)
    end)
    add("GetSpellAuraSecrecy=%s", sok and SecrecyName(secrecy) or "error")

    -- The substitution test. `escaping` non-nil means the game has swapped this
    -- spell for one the container's filter cannot match, so the reminder is
    -- held dark in Lua rather than by the container's geometry. A spell that
    -- reads escaping forever has a talent override no Cooldown Manager entry
    -- carries: its container could never match either aura, and the reminder
    -- is dark for that reason rather than because the buff is up.
    local escaping = SAU.EscapingOverrideFor(tracker.spellId)
    local ook, rawOverride = pcall(C_Spell.GetOverrideSpell, tracker.spellId)
    add("escaping=%s resolvedTo=%s displayedAs=%d GetOverrideSpell=%s idSetVersion=%s",
        escaping and tostring(escaping) or "none",
        tostring(SAU.ResolvedSpellFor(tracker.spellId)),
        SAU.DisplaySpellFor(tracker.spellId),
        ook and tostring(rawOverride) or "error",
        tostring(addon.AuraIds.GetVersion and addon.AuraIds.GetVersion()))
    add("gatereason=%s", tostring(Engine._results and Engine._results["gatereason.t" .. trackerId]))
    if tracker.unit ~= "group" then
        -- The group branch prints this per id with its own secrecy verdicts.
        add("includeSpellIDs=%s", table.concat(Missing.SpellIds(trackerId, tracker), ","))
    end

    if tracker.unit == "group" then
        Missing.AddGroupDebug(add, trackerId, tracker)
    end

    local state = SAU._activeStates[trackerId]
    local entry = state and state.entry
    if not entry then
        add("no pool entry (not claimed)")
        return lines
    end
    local results = Engine._results or {}
    add("build=%s wire=%s gate=%s", tostring(results["build.t" .. trackerId]),
        tostring(results["wire.t" .. trackerId]), tostring(results["gate.t" .. trackerId]))
    add("group=%s wiredKind=%s container=%s", tostring(entry.gateGroupKey),
        tostring(entry.wiredKind), tostring(entry.container ~= nil))
    if entry.container then
        -- Secret once the layout has run: the group sizes the container with
        -- secretwrap. A plain PUSH x 1 means no layout pass has landed yet.
        local wok, w = pcall(entry.container.GetWidth, entry.container)
        local hok, h = pcall(entry.container.GetHeight, entry.container)
        add("container size=%sx%s", wok and Describe(w) or ("error: " .. tostring(w)),
            hok and Describe(h) or ("error: " .. tostring(h)))
    end

    local m = entry.missing
    if not m then
        add("no visual built")
        return lines
    end
    add("clip shown=%s content shown=%s wired=%s templated=%s blink=%s host=%sx%s",
        tostring(m.clip:IsShown()), tostring(m.content:IsShown()), tostring(m.wired),
        tostring(m.templated), tostring(m.blink:IsPlaying()), tostring(entry.hostW), tostring(entry.hostH))
    -- The content's position follows the secret-sized container once anchored,
    -- so a secret here means the gate is live; a plain number means it is not.
    local lok, left = pcall(m.content.GetLeft, m.content)
    add("content:GetLeft()=%s", lok and Describe(left) or ("error: " .. tostring(left)))

    -- Plain reads for cross-checking; never throw (RequiresNonSecretAura
    -- returns nothing instead).
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local aok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, tracker.spellId)
        add("GetPlayerAuraBySpellID(%d)=%s", tracker.spellId, aok and Describe(aura) or ("error: " .. tostring(aura)))
    end
    return lines
end
