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
--    +- gate (Scoot)                                   level visual+3
--        +- root (Scoot)                               level visual+3
--            +- element set (Engine.BuildElementSet): the icon, the drain
--               Cooldown (the swipe on the Icon shape, and the natural-expiry
--               timer on both), the duration and stacks FontStrings (the
--               countdown and the charge count), the bar and the name on the
--               Bar shape
--            +- glow host (Scoot)                      level root+3
--                +- proc glow (addon.ProcGlow)
--
-- The Reactive Ability kind is this art with one more gate: an ability with
-- no aura that the game unlocks on a trigger (Riposte after a parry) shows
-- only through C_Spell.IsSpellUsable, re-read on SPELL_UPDATE_USABLE. Its
-- verdict is the gate frame's alpha, written through SetAlphaFromBoolean so
-- a plain and a secret answer take one path, and the frame sits between the
-- shell's state opacity and the root's ready pair so the three multiply.
-- The Spell Cooldown kind leaves the gate at 1.
--
-- The same kind can glow as a proc does on an action button (the Animations
-- tab). The glow host and the glow are built the first time a tracker asks
-- for them, and show while the spell is usable and off cooldown under
-- either "Show it..." rule.
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
-- [trackerId] = true, for the live trackers whose gate reads usability. The
-- usable event repaints these alone: it arrives on every power tick.
local liveUsable = {}
local repaintPending = false
local usablePending = false
local knownPending = false
local usableEvents = 0
local lastUsableEvent = nil

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

--- Whether the spell is cooling right now, by the flags the game never makes
-- secret: a charge spell with a recharge running, or a cooldown that is
-- active and is more than the GCD. The branch PaintValues takes for the
-- swipe, so a caller that shows art only while a spell cools (bonus.lua)
-- agrees with what the art then draws.
function Cooldown.IsCooling(base)
    local id = ResolveQueryId(base)
    local getCharges = SpellApi("GetSpellCharges")
    if getCharges then
        local ok, info = pcall(getCharges, id)
        if ok and type(info) == "table" and PlainNumber(info.maxCharges) and info.maxCharges > 1
            and PlainTrue(info.isActive) then
            return true
        end
    end
    local getCooldown = SpellApi("GetSpellCooldown")
    if getCooldown then
        local ok, info = pcall(getCooldown, id)
        if ok and type(info) == "table" then
            return PlainTrue(info.isActive) and not PlainTrue(info.isOnGCD)
        end
    end
    return false
end

--- Whether the spell can be cast right now, for the Reactive Ability kind.
-- "Usable but for power" counts as usable, so an ability the game has
-- unlocked still shows while the player is short of energy. Both returns
-- are documented plain on retail and on Forever; when either reads secret
-- the OR cannot run in Lua, and the first return goes to the sinks as it
-- came. Returns the verdict, a plain or a secret boolean, or nil when the
-- read failed, and a word for the debug window.
local function ReadUsable(id)
    local isUsable = SpellApi("IsSpellUsable")
    if not isUsable then return nil, "no api" end
    local ok, usable, noPower = pcall(isUsable, id)
    if not ok then return nil, "read failed" end
    if type(usable) ~= "boolean" then return nil, "no verdict" end
    if IsSecret(usable) or IsSecret(noPower) then return usable, "secret" end
    if usable then return true, "usable" end
    if noPower == true then return true, "usable, short of power" end
    return false, "unusable"
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
-- then zeroes the state it hides in both. `shell` is where the state fade
-- has the shell's alpha now (core/opacity.lua), when it holds one: mid-fade
-- the divide needs the alpha on screen, and the resolve answers the fade's
-- end. The Reactive Ability kind has no Priority System rows, so a value
-- carried over from a kind flip reads as 100, and its text never takes a
-- pair of its own: a host that ignores its parents would ignore the gate.
-- Its "Only while Usable" hides the cooling state like "ready" does; the
-- gate frame hides the unusable one.
-- Returns readyAlpha, cdAlpha, textOverride, readyText, cdText, shellAlpha.
local function ResolveAlphas(tracker, db, shell)
    local shellAlpha = shell or addon.Opacity.Resolve(db, addon.Opacity.Keys.InCombat)
    local artSetting = Pct(db and db.opacityOnCooldown)
    local textSetting = Pct(db and db.opacityOnCooldownText)
    local offMode = db ~= nil and db.cooldownOpacityMode == "offCooldown"
    if SAU.KindWatchesUsable(tracker.kind) then
        artSetting, textSetting, offMode = 100, 100, false
    end

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
    elseif rule == "ready" or rule == "usable" then
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

--- The element set and its value record under `root`, a frame the caller owns
-- and sizes. A cooldown that runs out fires no spell event; the Cooldown's
-- own completion script is the one signal there is, and `onDone` is what it
-- runs. The tracker path below and the bonus groups (bonus.lua) both build
-- through this, so PaintElementSet and PaintValues take either.
function Cooldown.BuildVisual(root, onDone)
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
    if found.cd and type(onDone) == "function" then
        found.cd.widget:SetScript("OnCooldownDone", onDone)
    end
    return cdv
end

local function EnsureVisual(entry)
    if entry.cooldown then return entry.cooldown end
    local visual = entry.visual

    -- Above the missing-state underlay (visual + 2), below a parked container
    -- (visual + 5) and the Edit Mode preview (visual + 10). The gate holds
    -- the usable alpha and nothing else; it stays shown and the root under
    -- it is what hides.
    local level = visual:GetFrameLevel() + 3
    local gate = CreateFrame("Frame", nil, visual)
    gate:SetAllPoints(visual)
    gate:SetFrameLevel(level)

    local root = CreateFrame("Frame", nil, gate)
    root:SetAllPoints(visual)
    root:SetFrameLevel(level)
    root:Hide()

    -- The completion script repaints the ready state, which is why the
    -- Cooldown is fed on the Bar shape too.
    local cdv = Cooldown.BuildVisual(root, function() Cooldown.RequestRepaint() end)
    cdv.gate = gate
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
    -- 0 or 1 in C, so a secret verdict still lands. A Reactive Ability
    -- tracker is gray while the spell is unusable too: a plain verdict
    -- decides in Lua, a secret one nests the two curves.
    local iconTex = cdv.icon and cdv.icon.widget
    if iconTex and vis.showIcon then
        local want = not db or db.cooldownDesaturate ~= false
        local verdict
        if want and SAU.KindWatchesUsable(tracker.kind) then verdict = ReadUsable(id) end
        if want and readyObj and EvalBool then
            local ok = pcall(function()
                local gray = EvalBool(readyObj:IsZero(), 0, 1)
                if type(verdict) == "boolean" then
                    if IsSecret(verdict) then
                        gray = EvalBool(verdict, gray, 1)
                    elseif not verdict then
                        gray = 1
                    end
                end
                iconTex:SetDesaturation(gray)
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

--- The Reactive Ability kind's alpha on the gate frame: 1 while the spell
-- can be cast and 0 while it cannot, under "Only while Usable". The verdict
-- goes through SetAlphaFromBoolean whether it reads plain or secret. Every
-- other case writes 1: the Spell Cooldown kind, "Always", Edit Mode, and a
-- read with no verdict, which fails open as the root does. A set built
-- without a gate (bonus.lua's cells) has nothing to write.
local function WriteUsableGate(tracker, cdv, editing)
    local gate = cdv.gate
    if not gate then return end
    local last = cdv.last
    if editing or not SAU.KindWatchesUsable(tracker.kind) then
        gate:SetAlpha(1)
        last.usable, last.usableGate = nil, nil
        return
    end
    local verdict, how = ReadUsable(cdv.resolved.id or ResolveQueryId(tracker.spellId))
    last.usable = how
    if type(verdict) ~= "boolean" then
        gate:SetAlpha(1)
        last.usableGate = "no verdict, open"
        return
    end
    if SAU.ShowWhenFor(tracker) ~= "usable" then
        gate:SetAlpha(1)
        last.usableGate = "always, open"
        return
    end
    local ok = pcall(gate.SetAlphaFromBoolean, gate, verdict, 1, 0)
    if not ok then gate:SetAlpha(1) end
    last.usableGate = ok and "set" or "failed, open"
end

--------------------------------------------------------------------------------
-- The proc glow (Reactive Ability kind, Animations tab)
--------------------------------------------------------------------------------

-- Above the icon border (root + 2) and below the text host (root + 4), the
-- level the pandemic border takes on an aura button.
local GLOW_LEVEL = 3

--- Places the glow on a restyle: built on first use, sized from the settings
-- the icon is sized from, and stopped and hidden when the tracker does not
-- ask for one. The host covers the icon and takes the usable alpha; the glow
-- under it takes the ready alpha, so the two multiply. A set built without
-- a gate (bonus.lua's cells) gets none.
local function LayoutGlow(tracker, cdv, db, vis)
    local iconElem = cdv.icon
    local watches = SAU.KindWatchesUsable(tracker.kind)
    local want = watches and cdv.gate ~= nil and iconElem ~= nil and vis.showIcon
        and db ~= nil and db.procGlow == true
    local hasArt = want and addon.ProcGlow.HasArt()
    if not hasArt then
        if cdv.glow then
            cdv.glow:Stop()
            cdv.glowHost:Hide()
        end
        cdv.glowOn, cdv.glowUsable = nil, nil
        cdv.last.glow = (want and "no atlas on this client") or (watches and "off") or nil
        return
    end

    local host = cdv.glowHost
    if not host then
        host = CreateFrame("Frame", nil, cdv.root)
        cdv.glowHost = host
        cdv.glow = addon.ProcGlow.Create(host)
    end
    host:ClearAllPoints()
    host:SetAllPoints(iconElem.widget)
    host:SetFrameLevel(cdv.root:GetFrameLevel() + GLOW_LEVEL)
    cdv.glow:SetFrameLevel(host:GetFrameLevel())
    local w, h = SAU.IconDimensions(db, vis)
    cdv.glow:Fit(host, w, h)
    host:Show()
    cdv.glowOn = true
end

--- The glow's two alphas and whether it animates, on every cooldown and
-- usable event. The glow shows while the spell is usable and off cooldown:
-- the verdict goes to the host and the ready object to the glow, each
-- through SetAlphaFromBoolean, so neither is tested here unless it reads
-- plain. A plain verdict also starts and stops the animation, and a change
-- from unusable to usable plays the burst; the first paint goes to the loop
-- as a refresh does on a Blizzard button. A secret verdict leaves the loop
-- running under the host's alpha with no burst, since no edge can be read.
-- With no verdict the glow hides: the icon fails open there, and a glow
-- that never ended would mislead.
local function WriteGlow(tracker, cdv, editing)
    if not cdv.glowOn then return end
    local host, glow, last = cdv.glowHost, cdv.glow, cdv.last
    if editing then
        host:SetAlpha(1)
        glow:SetAlpha(1)
        glow:Start(false)
        cdv.glowUsable = nil
        last.glow = "edit mode"
        return
    end

    local id = cdv.resolved.id or ResolveQueryId(tracker.spellId)
    local verdict = ReadUsable(id)
    if type(verdict) ~= "boolean" then
        glow:Stop()
        cdv.glowUsable = nil
        last.glow = "no verdict, hidden"
        return
    end

    local readyObj
    local get = SpellApi("GetSpellCooldownDuration")
    if get then
        local ok, obj = pcall(get, id, true)
        if ok and obj then readyObj = obj end
    end
    local okReady = readyObj ~= nil and pcall(function()
        glow:SetAlphaFromBoolean(readyObj:IsZero(), 1, 0)
    end)
    if not okReady then glow:SetAlpha(1) end

    if IsSecret(verdict) then
        local ok = pcall(host.SetAlphaFromBoolean, host, verdict, 1, 0)
        if ok then glow:Start(false) else glow:Stop() end
        cdv.glowUsable = nil
        last.glow = ok and "secret, loop" or "secret, failed, hidden"
        return
    end

    host:SetAlpha(1)
    if verdict then
        glow:Start(cdv.glowUsable == false)
        last.glow = "plain, running"
    else
        glow:Stop()
        last.glow = "plain, stopped"
    end
    cdv.glowUsable = verdict
end

--- Shows the root while the spell is known (or Edit Mode is open), then
-- writes the alphas ResolveAlphas computes from a fresh ready object: the
-- root through SetAlphaFromBoolean, and the text host the same way when its
-- value differs from the art's, ignoring its parents. With every value at
-- 100 and "Show it..." on Always nothing is fetched and the root reads 1.
-- The root is a child of the visual, so its alpha multiplies with the state
-- opacity the shell carries; the divide in ResolveAlphas keeps the product
-- at the stronger of the two. Edit Mode forces everything open: the preview
-- and the drag box live on this art. Runs on every cooldown event, and from
-- RefreshOpacity on the combat and target edges that move the shell, and on
-- the usable event for a Reactive Ability tracker.
function Cooldown.UpdateGate(trackerId)
    local state = SAU._activeStates[trackerId]
    local entry = state and state.entry
    local cdv = entry and entry.cooldown
    if not cdv then return end
    local tracker = SAU.GetTracker(trackerId)
    if not tracker or not SAU.KindUsesCooldownArt(tracker.kind) then return end
    local editing = SAU._isEditModeActive and SAU._isEditModeActive() or false
    local root = cdv.root
    local last = cdv.last

    root:SetShown(cdv.resolved.known ~= false or editing)
    WriteUsableGate(tracker, cdv, editing)
    WriteGlow(tracker, cdv, editing)
    -- A grouped tracker's slot opens and closes on the same reads.
    if SAU.Slots then SAU.Slots.Feed(trackerId) end

    if editing then
        root:SetAlpha(1)
        ReleaseText(cdv)
        last.gate = "edit mode"
        return
    end

    local readyAlpha, cdAlpha, textOverride, readyText, cdText, shellAlpha =
        ResolveAlphas(tracker, SAU.GetDB(trackerId), addon.Opacity.FadeValue(state))
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
-- The group slot (slots.lua)
--------------------------------------------------------------------------------

--- Whether the tracker shows anything, as a number for the bar that sizes its
-- slot in a group: `open` while it shows, `closed` while "Show it..." hides
-- it. The answer is plain or secret as the reads are, and is only ever handed
-- to StatusBar:SetValue. "Only while Usable" needs the spell castable and off
-- cooldown, so the usable verdict picks between the ready answer and
-- `closed`; where the client refuses a secret number there, the verdict
-- stands alone. nil when nothing could be read, which the caller takes as
-- open, the way the art fails open.
function Cooldown.SlotValue(trackerId, open, closed)
    local state = SAU._activeStates[trackerId]
    local cdv = state and state.entry and state.entry.cooldown
    local tracker = SAU.GetTracker(trackerId)
    if not (cdv and tracker and EvalBool and SAU.KindUsesCooldownArt(tracker.kind)) then
        return nil
    end
    local rule = SAU.ShowWhenFor(tracker)
    if rule == "always" then return open end

    local id = cdv.resolved.id or ResolveQueryId(tracker.spellId)
    local readyObj
    local get = SpellApi("GetSpellCooldownDuration")
    if get then
        local ok, obj = pcall(get, id, true)
        if ok and obj then readyObj = obj end
    end
    if not readyObj then return nil end

    local okReady, value = pcall(function()
        local ready = readyObj:IsZero()
        if rule == "oncooldown" then return EvalBool(ready, closed, open) end
        return EvalBool(ready, open, closed)
    end)
    if not okReady then return nil end
    if rule ~= "usable" then return value end

    local verdict = ReadUsable(id)
    if type(verdict) ~= "boolean" then return value end
    local okBoth, both = pcall(EvalBool, verdict, value, closed)
    if okBoth then return both end
    local okUsable, usable = pcall(EvalBool, verdict, open, closed)
    if okUsable then return usable end
    return nil
end

--- Whether a grouped tracker takes a slot at all: a spell the character does
-- not know has its art hidden outright, by a plain read. True for any
-- tracker this file does not draw.
function Cooldown.HoldsSlot(trackerId)
    local entry = live[trackerId]
    local cdv = entry and entry.cooldown
    if not cdv then return true end
    return cdv.resolved.known ~= false
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
    local wasKnown = cdv.resolved.known
    cdv.resolved.known = KnownHere(base, id)
    -- A spell learned or lost takes or gives up the tracker's group slot.
    if wasKnown ~= nil and wasKnown ~= cdv.resolved.known and entry.grouped and SAU.Groups then
        SAU.Groups.RequestReflow()
    end
    local shim = { container = cdv.root, elements = cdv.elements, entry = entry }
    Cooldown.PaintElementSet(trackerId, tracker, shim, cdv)
    local db = SAU.GetDB(trackerId)
    LayoutGlow(tracker, cdv, db, SAU.ResolveVisibility(tracker, db))
    Cooldown.PaintValues(trackerId, tracker, cdv, db)
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
    local watches = SAU.KindWatchesUsable(tracker.kind)
    liveUsable[trackerId] = watches or nil
    Engine._SetResult("build.t" .. trackerId,
        watches and "reactive ability (no container)" or "spell cooldown (no container)")
end

--- Hides the art and drops the tracker from the event fan-out. Safe for any
-- tracker id and for an entry that never built one.
function Cooldown.Release(trackerId, entry)
    if trackerId then
        live[trackerId] = nil
        liveUsable[trackerId] = nil
    end
    local cdv = entry and entry.cooldown
    if cdv then
        cdv.root:Hide()
        if cdv.gate then cdv.gate:SetAlpha(1) end
        if cdv.glow then
            cdv.glow:Stop()
            cdv.glowHost:Hide()
        end
        cdv.glowOn, cdv.glowUsable = nil, nil
        ReleaseText(cdv)
        if cdv.binding then pcall(cdv.binding.SetEnabled, cdv.binding, false) end
        if cdv.cd then pcall(cdv.cd.widget.Clear, cdv.cd.widget) end
    end
end

--- The one entry point from ApplyStyling, for every kind: a Spell Cooldown
-- or Reactive Ability tracker repaints, anything else on an entry that once
-- hosted one hides it.
function Cooldown.Sync(trackerId, tracker, state)
    if tracker and SAU.KindUsesCooldownArt(tracker.kind) then
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

--- Whether any live tracker's gate reads usability.
function Cooldown.AnyUsableLive()
    return next(liveUsable) ~= nil
end

-- `only`, when given, is a set of tracker ids: the rest are skipped, though
-- a stale one is still dropped.
local function ForEachLive(fn, only)
    for trackerId, entry in pairs(live) do
        local tracker = SAU.GetTracker(trackerId)
        local state = SAU._activeStates[trackerId]
        local cdv = entry.cooldown
        if tracker and SAU.KindUsesCooldownArt(tracker.kind) and state and state.entry == entry and cdv then
            if not only or only[trackerId] then
                fn(trackerId, tracker, entry, cdv)
            end
        else
            live[trackerId] = nil
            liveUsable[trackerId] = nil
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

--- SPELL_UPDATE_USABLE: the values and the gate for the Reactive Ability
-- trackers alone, once per frame. The event carries no spell and arrives on
-- every power tick, so nothing runs while no such tracker is live, and the
-- Spell Cooldown trackers are left out of the pass.
function Cooldown.OnUsableChanged()
    if not next(liveUsable) then return end
    usableEvents = usableEvents + 1
    lastUsableEvent = GetTime()
    if usablePending then return end
    usablePending = true
    C_Timer.After(0, function()
        usablePending = false
        ForEachLive(function(trackerId, tracker, entry, cdv)
            Cooldown.PaintValues(trackerId, tracker, cdv, SAU.GetDB(trackerId))
            Cooldown.UpdateGate(trackerId)
        end, liveUsable)
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
    local readyAlpha, cdAlpha, textOverride, readyText, cdText, shellAlpha =
        ResolveAlphas(tracker, db, addon.Opacity.FadeValue(SAU._activeStates[trackerId]))
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

    if SAU.KindWatchesUsable(tracker.kind) then
        add("")
        add("--- usable ---")
        local okU, usable, noPower = pcall(function() return C_Spell.IsSpellUsable(id) end)
        if okU then
            add("IsSpellUsable: isUsable=%s insufficientPower=%s", Describe(usable), Describe(noPower))
        else
            add("IsSpellUsable: error: %s", tostring(usable))
        end
        local _, how = ReadUsable(id)
        add("verdict=%s", tostring(how))
        local okO, glowing = pcall(function()
            return C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
                and C_SpellActivationOverlay.IsSpellOverlayed(id)
        end)
        add("IsSpellOverlayed=%s", okO and Describe(glowing) or "error")
        add("SPELL_UPDATE_USABLE: %d seen, last %s", usableEvents,
            lastUsableEvent and string.format("%.1fs ago", GetTime() - lastUsableEvent) or "never")
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
    if cdv.gate then
        local okGa, gateAlpha = pcall(cdv.gate.GetAlpha, cdv.gate)
        add("gate alpha=%s", okGa and Describe(gateAlpha) or "error")
    end
    add("--- last paint ---")
    local keys = {}
    for k in pairs(cdv.last) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        add("%s=%s", k, tostring(cdv.last[k]))
    end
    return lines
end
