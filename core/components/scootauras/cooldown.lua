-- scootauras/cooldown.lua - Spell Cooldown trackers: one spell's cooldown as
-- an icon or as a bar
--
-- The third kind that owns no AuraContainer, and the first with a spell.
-- Every element is Scoot art on entry.visual, fed by duration objects: the
-- swipe through SetCooldownFromDurationObject, the bar through
-- SetTimerDuration, the countdown through a DurationTextBinding, the ready
-- state through SetAlphaFromBoolean and a boolean curve on IsZero. The only
-- values branched on are the flags the game never makes secret (isActive,
-- isOnGCD, maxCharges); the timings and the charge count stay inside the
-- objects and the setters, so both shapes render in every secrecy state and
-- the structural gate never applies: creation, restyle, and shape flips are
-- legal mid-combat.
--
--   visual (Scoot, W x H from SetHostSize)
--    +- root (Scoot)                                   level visual+3
--        +- element set (Engine.BuildElementSet): the icon, the drain
--           Cooldown (the swipe on the Icon shape, and the natural-expiry
--           timer on both), the duration and stacks FontStrings (the
--           countdown and the charge count), the bar and the name on the
--           Bar shape
--
-- The ready state is one object. GetSpellCooldownDuration(id, ignoreGCD) is
-- zero-span while nothing but the GCD runs, and for a charge spell while any
-- charge remains (the regular cooldown carries the recharge only at zero
-- charges), so IsZero() on it answers "ready" for every spell with no
-- compare on the charge count. The swipe object is the recharge while a
-- charge is cooling, else that same object.
--
-- The Visibility tab's Priority System rows dim the tracker by cooldown
-- state (On or Off Cooldown; an art value and a text value) and compete
-- with the state opacity the shell carries: the stronger dim wins. The root
-- takes the art value with the shell's alpha divided out; the text host,
-- when its value differs, ignores its parents and takes an absolute pair.
-- "Show it..." zeroes the state it hides. The swipe follows the root (the
-- icon), not the text.
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = SAU.Engine

local Cooldown = {}
SAU.Cooldown = Cooldown

local DIR_ELAPSED = (Enum and Enum.StatusBarTimerDirection
    and Enum.StatusBarTimerDirection.ElapsedTime) or 0
local DIR_REMAINING = (Enum and Enum.StatusBarTimerDirection
    and Enum.StatusBarTimerDirection.RemainingTime) or 1
local INTERP_IMMEDIATE = (Enum and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.Immediate) or 0

-- A secret boolean into a number for SetDesaturation, evaluated in C.
local EvalBool = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean

-- The template's swipe, black at 0.64, pinned so no pass moves it.
local SWIPE_COLOR = { 0, 0, 0, 0.64 }

-- [trackerId] = entry, for the live trackers. The spell events repaint these
-- and nothing while the table is empty.
local live = {}
local repaintPending = false
local knownPending = false

--------------------------------------------------------------------------------
-- Secrecy helpers
--------------------------------------------------------------------------------

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

local function PlainNumber(v)
    return type(v) == "number" and not IsSecret(v)
end

-- A flag that reads secret is not a plain answer; the caller takes the
-- cautious branch.
local function PlainTrue(v)
    if IsSecret(v) then return false end
    return v == true
end

local function SpellApi(name)
    local fn = C_Spell and C_Spell[name]
    return type(fn) == "function" and fn or nil
end

--------------------------------------------------------------------------------
-- The spell: override and knowledge
--------------------------------------------------------------------------------

-- The spell whose cooldown runs: the talent override when one stands, else
-- the stored base. A secret or zero answer keeps the base.
local function ResolveQueryId(base)
    local get = SpellApi("GetOverrideSpell")
    if get then
        local ok, overrideID = pcall(get, base)
        if ok and type(overrideID) == "number" and not IsSecret(overrideID) and overrideID ~= 0 then
            return overrideID
        end
    end
    return base
end

-- Known or in the spellbook, by either id. An untaken talent has no cooldown
-- to show, so the art hides until the spell is learned.
local function KnownHere(base, resolved)
    if SAU.CharacterKnowsSpell(base) then return true end
    return resolved ~= base and SAU.CharacterKnowsSpell(resolved)
end

--------------------------------------------------------------------------------
-- The alphas: "Show it..." and the Priority System rows
--------------------------------------------------------------------------------

local function Pct(v)
    local n = tonumber(v)
    if not n then return 100 end
    if n < 0 then return 0 elseif n > 100 then return 100 end
    return n
end

--- The ready and on-cooldown alphas for the root and for the text host, from
-- the tracker's settings and the state opacity the shell carries right now
-- (the same resolve styling.lua makes, never read back from the frame). The
-- root's dim is divided by the shell's alpha, so the two multiply to the
-- smaller of them rather than stacking. The text host, when its value
-- differs from the art's in On Cooldown mode, ignores its parents and takes
-- an absolute pair: the shell's alpha when ready, the smaller of it and the
-- text dim when cooling. Off Cooldown swaps the root's pair. "Show it..."
-- then zeroes the state it hides in both.
-- Returns readyAlpha, cdAlpha, textOverride, readyText, cdText, shellAlpha.
local function ResolveAlphas(tracker, db)
    local shellAlpha = addon.Opacity.Resolve(db, addon.Opacity.Keys.InCombat)
    local artSetting = Pct(db and db.opacityOnCooldown)
    local textSetting = Pct(db and db.opacityOnCooldownText)
    local offMode = db ~= nil and db.cooldownOpacityMode == "offCooldown"

    local dim = artSetting / 100
    if artSetting < 100 and shellAlpha > 0 and shellAlpha < 1 then
        dim = math.min(1, dim / shellAlpha)
    end
    local readyAlpha, cdAlpha = 1, dim
    if offMode then readyAlpha, cdAlpha = dim, 1 end
    local textOverride = not offMode and textSetting ~= artSetting
    local readyText, cdText = shellAlpha, math.min(shellAlpha, textSetting / 100)

    local rule = SAU.ShowWhenFor(tracker)
    if rule == "oncooldown" then
        readyAlpha, readyText = 0, 0
    elseif rule == "ready" then
        cdAlpha, cdText = 0, 0
    end
    return readyAlpha, cdAlpha, textOverride, readyText, cdText, shellAlpha
end

--- Puts the text host back under its parents' alpha: whenever the text
-- takes no value of its own, and on release, so a later occupant of the
-- entry inherits.
local function ReleaseText(cdv)
    if not cdv.textDecoupled then return end
    local host = cdv.textFrame
    if host then
        pcall(host.SetIgnoreParentAlpha, host, false)
        host:SetAlpha(1)
    end
    cdv.textDecoupled = nil
end

--------------------------------------------------------------------------------
-- Scoot-owned visual (per pool entry, session-permanent)
--------------------------------------------------------------------------------

local function FindElements(elements)
    local found = {}
    for _, elem in ipairs(elements or {}) do
        if elem.type == "texture" then
            found.icon = elem
        elseif elem.type == "text" then
            local source = elem.def.source
            if source == "duration" then
                found.duration = elem
            elseif source == "name" then
                found.name = elem
            elseif source == "applications" then
                found.stacks = elem
            end
        elseif elem.type == "bar" then
            found.bar = elem
        elseif elem.type == "cooldown" then
            found.cd = elem
        end
    end
    return found
end

-- The countdown's binding, built once per set. The engine writes the
-- FontString from the duration object on its own schedule; a failed build
-- leaves the text hidden rather than erroring on every event.
local function BuildBinding(fs)
    local du = C_DurationUtil
    if not (fs and du and du.CreateDurationTextBinding) then return false end
    local ok, binding = pcall(du.CreateDurationTextBinding)
    if not ok or not binding then return false end
    local built = pcall(function()
        binding:SetFontString(fs)
        -- Zero: every game tick, so tenths never step.
        binding:SetUpdateInterval(0)
        binding:SetExpiredText("")
        binding:SetZeroDurationText("")
    end)
    return built and binding or false
end

local function EnsureVisual(entry)
    if entry.cooldown then return entry.cooldown end
    local visual = entry.visual

    -- Above the missing-state underlay (visual + 2), below a parked container
    -- (visual + 5) and the Edit Mode preview (visual + 10).
    local root = CreateFrame("Frame", nil, visual)
    root:SetAllPoints(visual)
    root:SetFrameLevel(visual:GetFrameLevel() + 3)
    root:Hide()

    local set = Engine.BuildElementSet(root)
    local found = FindElements(set.elements)

    local cdv = {
        root = root,
        elements = set.elements,
        textFrame = set.textFrame,
        icon = found.icon,
        duration = found.duration,
        name = found.name,
        stacks = found.stacks,
        bar = found.bar,
        cd = found.cd,
        binding = BuildBinding(found.duration and found.duration.widget),
        last = {},
        resolved = {},
    }
    -- A cooldown that runs out fires no spell event. The Cooldown's own
    -- completion script is what repaints the ready state then, which is why
    -- the Cooldown is fed on the Bar shape too.
    if found.cd then
        found.cd.widget:SetScript("OnCooldownDone", function() Cooldown.RequestRepaint() end)
    end
    entry.cooldown = cdv
    return cdv
end

--------------------------------------------------------------------------------
-- Values (per event: setters only)
--------------------------------------------------------------------------------

--- Feeds the cooldown into the swipe, the bar, the countdown and the charge
-- count. Nothing here reads a timing back: the objects carry the secrecy
-- into the sinks, and every verdict written to cdv.last describes the call,
-- never the value. Runs on every cooldown event, so it stays a handful of
-- calls.
function Cooldown.PaintValues(trackerId, tracker, cdv, db)
    local last = cdv.last
    local vis = SAU.ResolveVisibility(tracker, db)
    local id = cdv.resolved.id or ResolveQueryId(tracker.spellId)

    local getCooldown = SpellApi("GetSpellCooldown")
    local getCharges = SpellApi("GetSpellCharges")
    local getCooldownDur = SpellApi("GetSpellCooldownDuration")
    local getChargeDur = SpellApi("GetSpellChargeDuration")

    local cdInfo, chargeInfo, readyObj
    if getCooldown then
        local ok, info = pcall(getCooldown, id)
        if ok and type(info) == "table" then cdInfo = info end
    end
    if getCharges then
        local ok, info = pcall(getCharges, id)
        if ok and type(info) == "table" then chargeInfo = info end
    end
    if getCooldownDur then
        local ok, obj = pcall(getCooldownDur, id, true)
        if ok and obj then readyObj = obj end
    end

    -- maxCharges and both isActive flags are never secret; a secret one here
    -- would be a changed annotation, and the plain tests keep the compare
    -- off it.
    local charges = chargeInfo ~= nil and PlainNumber(chargeInfo.maxCharges)
        and chargeInfo.maxCharges > 1
    local swipeObj
    if charges and PlainTrue(chargeInfo.isActive) then
        if getChargeDur then
            local ok, obj = pcall(getChargeDur, id)
            if ok and obj then swipeObj = obj end
        end
        last.source = swipeObj and "recharge" or "recharge (no object)"
    elseif cdInfo and PlainTrue(cdInfo.isActive) and not PlainTrue(cdInfo.isOnGCD) then
        swipeObj = readyObj
        last.source = swipeObj and "cooldown" or "cooldown (no object)"
    else
        last.source = "ready"
    end

    -- The swipe, on both shapes: the Icon shape draws it, and the completion
    -- script runs on both.
    local cd = cdv.cd and cdv.cd.widget
    if cd then
        if swipeObj then
            local ok = pcall(cd.SetCooldownFromDurationObject, cd, swipeObj)
            last.swipe = ok and "set" or "set failed"
        else
            pcall(cd.Clear, cd)
            last.swipe = "clear"
        end
    end

    -- The bar: the engine ticks the fill from the object. Fill grows as the
    -- cooldown recovers and is full when ready; Deplete starts full and
    -- empties. A plain SetValue cancels a running timer, which is the ready
    -- state.
    local barFill = cdv.bar and cdv.bar.barFill
    if barFill and vis.showBar then
        local fillUp = (db and db.barFillMode) == "fill"
        if swipeObj then
            local ok = pcall(barFill.SetTimerDuration, barFill, swipeObj, INTERP_IMMEDIATE,
                fillUp and DIR_ELAPSED or DIR_REMAINING)
            last.bar = ok and "timer" or "timer failed"
        else
            barFill:SetMinMaxValues(0, 1)
            barFill:SetValue(fillUp and 1 or 0)
            last.bar = "ready"
        end
    else
        last.bar = "no bar"
    end

    -- The countdown: the binding writes the FontString from the object on
    -- every tick, with the Duration tab's formatter (plain seconds, or
    -- tenths). A zero-span object writes the empty zero text.
    local durationFS = cdv.duration and cdv.duration.widget
    local binding = cdv.binding
    if durationFS then
        if vis.showText and binding then
            local tenths = db and db.textDecimal == true
            local formatter = Engine.GetDurationFormatter(tenths)
                or (tenths and Engine.GetDurationFormatter(false)) or nil
            if formatter then pcall(binding.SetFormatter, binding, formatter) end
            local obj = swipeObj or readyObj
            local bound = obj ~= nil and pcall(binding.SetDuration, binding, obj)
            pcall(binding.SetEnabled, binding, bound and true or false)
            durationFS:SetShown(bound and true or false)
            last.text = bound and "bound" or "no object"
        else
            if binding then pcall(binding.SetEnabled, binding, false) end
            durationFS:Hide()
            last.text = vis.showText and "no binding" or "hidden"
        end
    end

    -- The charge count: a secret number goes to SetText as it is. ClearText
    -- first, the one call that releases the Text aspect the last paint
    -- stamped.
    local stacksFS = cdv.stacks and cdv.stacks.widget
    if stacksFS then
        if stacksFS.ClearText then stacksFS:ClearText() else stacksFS:SetText("") end
        if charges and vis.showStacks then
            local ok = pcall(stacksFS.SetText, stacksFS, chargeInfo.currentCharges)
            stacksFS:SetShown(ok)
            last.charges = ok and "set" or "set failed"
        else
            stacksFS:Hide()
            last.charges = charges and "hidden" or "no charges"
        end
    end

    -- Desaturation while on cooldown: the boolean curve turns IsZero into
    -- 0 or 1 in C, so a secret verdict still lands.
    local iconTex = cdv.icon and cdv.icon.widget
    if iconTex and vis.showIcon then
        local want = not db or db.cooldownDesaturate ~= false
        if want and readyObj and EvalBool then
            local ok = pcall(function()
                iconTex:SetDesaturation(EvalBool(readyObj:IsZero(), 0, 1))
            end)
            if not ok then pcall(iconTex.SetDesaturation, iconTex, 0) end
            last.desat = ok and "curve" or "curve failed"
        else
            pcall(iconTex.SetDesaturation, iconTex, 0)
            last.desat = want and "no object" or "off"
        end
    end
end

--------------------------------------------------------------------------------
-- The gate: the known spell, "Show it...", and the dim
--------------------------------------------------------------------------------

--- Shows the root while the spell is known (or Edit Mode is open), then
-- writes the alphas ResolveAlphas computes from a fresh ready object: the
-- root through SetAlphaFromBoolean, and the text host the same way when its
-- value differs from the art's, ignoring its parents. With every value at
-- 100 and "Show it..." on Always nothing is fetched and the root reads 1.
-- The root is a child of the visual, so its alpha multiplies with the state
-- opacity the shell carries; the divide in ResolveAlphas keeps the product
-- at the stronger of the two. Edit Mode forces everything open: the preview
-- and the drag box live on this art. Runs on every cooldown event, and from
-- RefreshOpacity on the combat and target edges that move the shell.
function Cooldown.UpdateGate(trackerId)
    local state = SAU._activeStates[trackerId]
    local entry = state and state.entry
    local cdv = entry and entry.cooldown
    if not cdv then return end
    local tracker = SAU.GetTracker(trackerId)
    if not tracker or tracker.kind ~= "cooldown" then return end
    local editing = SAU._isEditModeActive and SAU._isEditModeActive() or false
    local root = cdv.root
    local last = cdv.last

    root:SetShown(cdv.resolved.known ~= false or editing)

    if editing then
        root:SetAlpha(1)
        ReleaseText(cdv)
        last.gate = "edit mode"
        return
    end

    local readyAlpha, cdAlpha, textOverride, readyText, cdText, shellAlpha =
        ResolveAlphas(tracker, SAU.GetDB(trackerId))
    last.alphas = string.format("shell %.2f root %.2f/%.2f text %s", shellAlpha, readyAlpha, cdAlpha,
        textOverride and string.format("%.2f/%.2f", readyText, cdText) or "inherits")
    if readyAlpha == 1 and cdAlpha == 1 and not textOverride then
        root:SetAlpha(1)
        ReleaseText(cdv)
        last.gate = "open"
        return
    end

    local readyObj
    local get = SpellApi("GetSpellCooldownDuration")
    if get then
        local ok, obj = pcall(get, cdv.resolved.id or ResolveQueryId(tracker.spellId), true)
        if ok and obj then readyObj = obj end
    end
    if not readyObj then
        root:SetAlpha(1)
        ReleaseText(cdv)
        last.gate = "no object, open"
        return
    end

    local okRoot = pcall(function()
        root:SetAlphaFromBoolean(readyObj:IsZero(), readyAlpha, cdAlpha)
    end)
    if not okRoot then root:SetAlpha(1) end

    local host = cdv.textFrame
    local okText = true
    if textOverride and host then
        cdv.textDecoupled = true
        okText = pcall(function()
            host:SetIgnoreParentAlpha(true)
            host:SetAlphaFromBoolean(readyObj:IsZero(), readyText, cdText)
        end)
        if not okText then ReleaseText(cdv) end
    else
        ReleaseText(cdv)
    end
    last.gate = (okRoot and "root set" or "root failed, open")
        .. (textOverride and (okText and ", text set" or ", text failed, inherits") or "")
end

--------------------------------------------------------------------------------
-- Styling and layout (Tier 1: Scoot frames only)
--------------------------------------------------------------------------------

--- Paints one Scoot-owned element set as the tracker: the shared styling and
-- layout chain, then everything the kind never shows on this shape hidden,
-- then the swipe set up after the chain, which turns a non-shape tracker's
-- swipe off on every pass. `shim` is the chain's state table for that set
-- ({ container, elements, entry }). The values are painted separately
-- (PaintValues): they move on every cooldown event, and the chain does not.
function Cooldown.PaintElementSet(trackerId, tracker, shim, cdv)
    local db = SAU.GetDB(trackerId)
    local vis = SAU.ResolveVisibility(tracker, db)
    local isBar = SAU.IsBarShape(tracker.shape)

    SAU._ApplyIconMode(trackerId, tracker, shim)
    SAU._ApplyShapeStyling(trackerId, tracker, shim)
    SAU._ApplyBorders(trackerId, tracker, shim)
    SAU._ApplyBarStyling(trackerId, tracker, shim)
    SAU._ApplyTextStyling(trackerId, tracker, shim)

    -- The name is written here, not by an engine binding, and before the
    -- layout: the outside-text path measures the string present.
    local nameFS = cdv.name and cdv.name.widget
    if nameFS then
        if isBar and vis.showName then
            nameFS:SetText((SAU.DescribeSpell(tracker.spellId)) or "")
            nameFS:Show()
        else
            nameFS:SetText("")
            nameFS:Hide()
        end
    end

    SAU._LayoutElements(trackerId, tracker, shim)

    local iconElem = cdv.icon
    local iconShown = iconElem ~= nil and vis.showIcon
    if iconElem then
        if not iconShown then
            iconElem.widget:Hide()
            if iconElem.borderFrame then iconElem.borderFrame:Hide() end
        end
        if iconElem.silhouette then iconElem.silhouette:Hide() end
    end
    if cdv.bar and not vis.showBar then cdv.bar.widget:Hide() end

    -- The swipe: the template's dark sweep running forward over the icon,
    -- the action button look. Drawn on the Icon shape alone (a bar's side
    -- icon stays static; the fill shows the time), shown and fed on both so
    -- the completion script fires on both.
    local cdElem = cdv.cd
    if cdElem then
        local cd, clip = cdElem.widget, cdElem.clip
        local host = (iconShown and iconElem.widget) or shim.container
        if clip then
            clip:ClearAllPoints()
            clip:SetAllPoints(host)
        end
        cd:ClearAllPoints()
        cd:SetAllPoints(clip or host)
        cd:SetReverse(false)
        cd:SetDrawEdge(false)
        cd:SetDrawBling(false)
        cd:SetHideCountdownNumbers(true)
        pcall(cd.SetSwipeColor, cd, SWIPE_COLOR[1], SWIPE_COLOR[2], SWIPE_COLOR[3], SWIPE_COLOR[4])
        pcall(cd.SetDrawSwipe, cd, (not isBar) and iconShown and true or false)
        if cdElem.backdrop then cdElem.backdrop:Hide() end
        if cdElem.shade then cdElem.shade:Hide() end
        cd:Show()
    end
end

local function PaintLive(trackerId, tracker, entry, cdv)
    local base = tracker.spellId
    local id = ResolveQueryId(base)
    cdv.resolved.base = base
    cdv.resolved.id = id
    cdv.resolved.known = KnownHere(base, id)
    local shim = { container = cdv.root, elements = cdv.elements, entry = entry }
    Cooldown.PaintElementSet(trackerId, tracker, shim, cdv)
    Cooldown.PaintValues(trackerId, tracker, cdv, SAU.GetDB(trackerId))
    Cooldown.UpdateGate(trackerId)
end

--- Full Tier 1 pass for one live tracker: build the art on first use, paint
-- it, feed the values, apply the gate, and join the event fan-out.
function Cooldown.Restyle(trackerId, tracker, state)
    local entry = state and state.entry
    if not entry then return end
    local cdv = EnsureVisual(entry)
    PaintLive(trackerId, tracker, entry, cdv)
    live[trackerId] = entry
    Engine._SetResult("build.t" .. trackerId, "spell cooldown (no container)")
end

--- Hides the art and drops the tracker from the event fan-out. Safe for any
-- tracker id and for an entry that never built one.
function Cooldown.Release(trackerId, entry)
    if trackerId then live[trackerId] = nil end
    local cdv = entry and entry.cooldown
    if cdv then
        cdv.root:Hide()
        ReleaseText(cdv)
        if cdv.binding then pcall(cdv.binding.SetEnabled, cdv.binding, false) end
        if cdv.cd then pcall(cdv.cd.widget.Clear, cdv.cd.widget) end
    end
end

--- The one entry point from ApplyStyling, for every kind: a Spell Cooldown
-- tracker repaints, anything else on an entry that once hosted one hides it.
function Cooldown.Sync(trackerId, tracker, state)
    if tracker and tracker.kind == "cooldown" then
        Cooldown.Restyle(trackerId, tracker, state)
    else
        Cooldown.Release(trackerId, state and state.entry)
    end
end

-- The art is not torn down: pool frames are session-permanent, and the next
-- occupant's Sync repaints it or leaves it hidden.
function Cooldown.OnEntryReleased(entry, trackerId)
    Cooldown.Release(trackerId or (entry and entry.occupantId), entry)
end

--------------------------------------------------------------------------------
-- Events (registered on the bus by events.lua; dispatched here)
--------------------------------------------------------------------------------

function Cooldown.AnyLive()
    return next(live) ~= nil
end

local function ForEachLive(fn)
    for trackerId, entry in pairs(live) do
        local tracker = SAU.GetTracker(trackerId)
        local state = SAU._activeStates[trackerId]
        local cdv = entry.cooldown
        if tracker and tracker.kind == "cooldown" and state and state.entry == entry and cdv then
            fn(trackerId, tracker, entry, cdv)
        else
            live[trackerId] = nil
        end
    end
end

--- The values and the gate, for every live tracker, once per frame however
-- many cooldown events arrive in it.
function Cooldown.RequestRepaint()
    if repaintPending or not next(live) then return end
    repaintPending = true
    C_Timer.After(0, function()
        repaintPending = false
        ForEachLive(function(trackerId, tracker, entry, cdv)
            Cooldown.PaintValues(trackerId, tracker, cdv, SAU.GetDB(trackerId))
            Cooldown.UpdateGate(trackerId)
        end)
    end)
end

--- The whole paint, for every live tracker: a talent or a spec change can
-- move the override, the icon and whether the spell is known.
function Cooldown.RefreshKnown()
    if knownPending or not next(live) then return end
    knownPending = true
    C_Timer.After(0, function()
        knownPending = false
        ForEachLive(function(trackerId, tracker, entry, cdv)
            PaintLive(trackerId, tracker, entry, cdv)
        end)
    end)
end

--------------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------------

local function Describe(v)
    if IsSecret(v) then return "secret" end
    if type(v) == "table" then return "table" end
    return tostring(v)
end

--- Lines for /<slash> debug sa cooldown <id>: the spell, what each read
-- returns right now and whether it is secret, the gate, and the last paint.
function Cooldown.DebugInfo(trackerId)
    local lines, add = addon.DebugLines()

    local tracker = SAU.GetTracker(trackerId)
    if not tracker then
        add("t%s: no such tracker", tostring(trackerId))
        return lines
    end
    local db = SAU.GetDB(trackerId)
    add("t%d name=%q kind=%s shape=%s spell=%s showWhen=%s onlyInCombat=%s enabled=%s",
        trackerId, SAU.DisplayName(tracker), tostring(tracker.kind), tostring(tracker.shape),
        tostring(tracker.spellId), SAU.ShowWhenFor(tracker), tostring(tracker.onlyInCombat),
        tostring(tracker.enabled))
    add("desaturate=%s textDecimal=%s fillMode=%s hideText=%s hideStackText=%s",
        tostring(db and db.cooldownDesaturate), tostring(db and db.textDecimal),
        tostring(db and db.barFillMode), tostring(db and db.hideText),
        tostring(db and db.hideStackText))
    add("InCombatLockdown=%s editMode=%s gateOpen=%s active=%s",
        tostring(InCombatLockdown()),
        tostring(SAU._isEditModeActive and SAU._isEditModeActive()),
        tostring(SAU.CombatGateOpen(tracker)), tostring(SAU.IsTrackerActive(trackerId, tracker)))

    add("")
    add("--- alpha ---")
    add("opacityMode=%s art=%s text=%s",
        tostring(db and db.cooldownOpacityMode), tostring(db and db.opacityOnCooldown),
        tostring(db and db.opacityOnCooldownText))
    local readyAlpha, cdAlpha, textOverride, readyText, cdText, shellAlpha = ResolveAlphas(tracker, db)
    add("shell=%.2f root ready=%.2f cooling=%.2f text=%s", shellAlpha, readyAlpha, cdAlpha,
        textOverride and string.format("ready=%.2f cooling=%.2f (own)", readyText, cdText) or "inherits")

    add("")
    add("--- spell ---")
    local base = tracker.spellId
    local id = ResolveQueryId(base)
    add("base=%s resolved=%s knows(base)=%s knows(resolved)=%s PlayerHasSpell=%s",
        tostring(base), tostring(id), tostring(SAU.CharacterKnowsSpell(base)),
        tostring(SAU.CharacterKnowsSpell(id)), tostring(SAU.PlayerHasSpell(base)))
    local secrets = C_Secrets
    if secrets then
        local okA, all = pcall(function()
            return secrets.ShouldCooldownsBeSecret and secrets.ShouldCooldownsBeSecret()
        end)
        local okS, one = pcall(function()
            return secrets.ShouldSpellCooldownBeSecret and secrets.ShouldSpellCooldownBeSecret(id)
        end)
        add("ShouldCooldownsBeSecret=%s ShouldSpellCooldownBeSecret=%s",
            okA and Describe(all) or "error", okS and Describe(one) or "error")
    end
    local okC, info = pcall(function() return C_Spell.GetSpellCooldown(id) end)
    if okC and type(info) == "table" then
        add("GetSpellCooldown: isActive=%s isEnabled=%s isOnGCD=%s startTime=%s duration=%s modRate=%s",
            Describe(info.isActive), Describe(info.isEnabled), Describe(info.isOnGCD),
            Describe(info.startTime), Describe(info.duration), Describe(info.modRate))
    else
        add("GetSpellCooldown: %s", okC and "nil" or ("error: " .. tostring(info)))
    end
    local okH, charges = pcall(function() return C_Spell.GetSpellCharges(id) end)
    if okH and type(charges) == "table" then
        add("GetSpellCharges: maxCharges=%s currentCharges=%s isActive=%s",
            Describe(charges.maxCharges), Describe(charges.currentCharges), Describe(charges.isActive))
    else
        add("GetSpellCharges: %s", okH and "nil" or ("error: " .. tostring(charges)))
    end
    local okR, obj = pcall(function() return C_Spell.GetSpellCooldownDuration(id, true) end)
    if okR and obj then
        local okZ, zero = pcall(obj.IsZero, obj)
        local okV, hasSecret = pcall(obj.HasSecretValues, obj)
        add("GetSpellCooldownDuration(ignoreGCD): IsZero=%s HasSecretValues=%s",
            okZ and Describe(zero) or "error", okV and Describe(hasSecret) or "error")
    else
        add("GetSpellCooldownDuration: %s", okR and "nil" or ("error: " .. tostring(obj)))
    end

    add("")
    add("--- entry ---")
    local state = SAU._activeStates[trackerId]
    local entry = state and state.entry
    if not entry then
        add("no active entry (not claimed)")
        return lines
    end
    add("wired=%s parkedContainer=%s host=%sx%s grouped=%s live=%s",
        tostring(entry.wired), tostring(entry.container ~= nil), tostring(entry.hostW),
        tostring(entry.hostH), tostring(entry.grouped), tostring(live[trackerId] == entry))
    local cdv = entry.cooldown
    if not cdv then
        add("no cooldown art on this entry")
        return lines
    end
    local okSh, shown = pcall(cdv.root.IsShown, cdv.root)
    local okAl, alpha = pcall(cdv.root.GetAlpha, cdv.root)
    add("root shown=%s alpha=%s known=%s binding=%s textDecoupled=%s",
        okSh and tostring(shown) or "error", okAl and Describe(alpha) or "error",
        tostring(cdv.resolved.known), cdv.binding and "built" or "none",
        tostring(cdv.textDecoupled or false))
    add("--- last paint ---")
    local keys = {}
    for k in pairs(cdv.last) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        add("%s=%s", k, tostring(cdv.last[k]))
    end
    return lines
end
