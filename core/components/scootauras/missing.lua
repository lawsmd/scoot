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

--- Anchors the content to the container's right edge and shows it. Runs once
-- per fresh container; a revived container keeps its anchor.
function Missing.OnBuilt(trackerId, entry, container)
    local m = EnsureVisual(entry)
    m.content:ClearAllPoints()
    local ok, err = pcall(m.content.SetPoint, m.content, "LEFT", container, "RIGHT", 0, 0)
    if ok then
        m.content:Show()
        m.wired = true
        Engine._SetResult("gate.t" .. trackerId,
            m.templated and "anchored" or "anchored (plain frame; template missing)")
    else
        m.content:Hide()
        m.wired = false
        Engine._SetResult("gate.t" .. trackerId, "anchor FAILED: " .. tostring(err))
    end
end

--- The container that gated the content is being retired; the content anchor
-- now points at a parked frame. Hide until the next build re-anchors.
function Missing.OnRetire(entry)
    entry.gateGroupKey = nil
    local m = entry.missing
    if not m then return end
    m.wired = false
    m.content:Hide()
end

function Missing.OnEntryReleased(entry)
    local m = entry.missing
    if not m then return end
    m.clip:Hide()
    if m.blink:IsPlaying() then m.blink:Stop() end
    m.content:SetAlpha(1)
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
-- Plain-state gate: enable, Only in Combat, Edit Mode, blink
--------------------------------------------------------------------------------

--- Shows or hides the clip window from plain state only. Presence is never
-- consulted: the engine handles that by geometry. Safe for any tracker id;
-- a non-missing occupant of an entry that once hosted a reminder hides it.
function Missing.UpdateGate(trackerId)
    local state = SAU._activeStates[trackerId]
    local entry = state and state.entry
    local m = entry and entry.missing
    if not m then return end

    local tracker = SAU.GetTracker(trackerId)
    local db = SAU.GetDB(trackerId)
    local show = tracker ~= nil
        and tracker.kind == "missingbuff"
        and tracker.enabled ~= false
        and SAU.IsModuleActive()
    if show and tracker.onlyInCombat ~= false and not InCombatLockdown() then
        show = false
    end
    if show and SAU._isEditModeActive and SAU._isEditModeActive() then
        -- The Edit Mode preview stands in for the live reminder.
        show = false
    end
    m.clip:SetShown(show)

    local wantBlink = show and db ~= nil and db.blinkWhenShown == true
    if wantBlink then
        if not m.blink:IsPlaying() then m.blink:Play() end
    else
        if m.blink:IsPlaying() then m.blink:Stop() end
        m.content:SetAlpha(1)
    end
end

--- Regen events: re-evaluate every live reminder's gate.
function Missing.OnCombatChanged()
    for trackerId in pairs(SAU._activeStates) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and tracker.kind == "missingbuff" then
            Missing.UpdateGate(trackerId)
        end
    end
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
    add("t%d spell=%d kind=%s shape=%s onlyInCombat=%s enabled=%s",
        trackerId, tracker.spellId, tostring(tracker.kind), tostring(tracker.shape),
        tostring(tracker.onlyInCombat), tostring(tracker.enabled))
    add("text=%q suffix=%s blink=%s anchor=%s",
        Missing.ReminderText(tracker, db), tostring(db and db.missingSuffix),
        tostring(db and db.blinkWhenShown), tostring(db and db.nameTextOuterAnchor))
    add("InCombatLockdown=%s AurasSecretNow=%s editMode=%s",
        tostring(InCombatLockdown()), tostring(addon.AurasSecretNow and addon.AurasSecretNow()),
        tostring(SAU._isEditModeActive and SAU._isEditModeActive()))

    local sok, secrecy = pcall(function()
        return C_Secrets and C_Secrets.GetSpellAuraSecrecy and C_Secrets.GetSpellAuraSecrecy(tracker.spellId)
    end)
    add("GetSpellAuraSecrecy=%s", sok and (SECRECY_NAMES[secrecy] or Describe(secrecy)) or "error")

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
