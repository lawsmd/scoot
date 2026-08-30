--------------------------------------------------------------------------------
-- castbarz/events.lua
-- Cast lifecycle: start, update, finish, and the engine-driven progress handoff.
--
-- Z owns its frames, so nothing here hooks a Blizzard cast bar. One event frame
-- per unit, registered with RegisterUnitEvent exactly as Blizzard's own bar does
-- (Blizzard_UIPanels_Game/Mainline/CastingBarFrame.lua:122-134).
--
-- There is no OnUpdate anywhere in Cast Bar Z. Progress is handed to C++ via
-- StatusBar:SetTimerDuration and the reveal frame is anchored to the resulting
-- fill texture, so the sweep costs nothing per frame and never reads a value
-- back. Measured working on both plain and secret-valued durations.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CBZ = addon.CastBarZ

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

-- Chosen, not ported: Blizzard drives its own hold/fade through animation groups
-- rather than named constants, so there is nothing to copy. These read close to
-- the stock bar in practice.
local HOLD_COMPLETE = 0.35
local HOLD_FAILED   = 0.70
local FADE_TIME     = 0.25

-- Interrupt / failure presentation. The glow's peak alpha belongs to the texture,
-- not to this file: it depends on which art the frame ended up with (frames.lua).
-- Blizzard fades InterruptGlow over 1.0s (CastingBarFrame.xml:188); shortened here
-- so the glow is spent before the bar itself starts fading at HOLD_FAILED.
-- Two reds, not one. The name sits directly on the line, so a single red made the
-- word and its backdrop the same value and the text stopped separating. The line
-- goes lighter (toward white) and the text darker, splitting them either side of
-- the original 0.95/0.35/0.30.
local FAIL_LINE_COLOR = { 0.96, 0.48, 0.44 }
local FAIL_TEXT_COLOR = { 0.76, 0.28, 0.24 }
local FLASH_TIME = 0.60

--------------------------------------------------------------------------------
-- Reading cast state
--------------------------------------------------------------------------------

-- `type(x) == "nil"` rather than `x == nil`: on a restricted unit `name` is a
-- secret, and comparing a secret throws. type() answers on secrets, so this
-- distinguishes "not casting" from "casting something unreadable" without ever
-- touching the value. Guard order is always type() -> issecretvalue() -> compare.
local function IsCasting(unit)
    local name = UnitCastingInfo(unit)
    return type(name) ~= "nil"
end

local function IsChannelling(unit)
    local name = UnitChannelInfo(unit)
    return type(name) ~= "nil"
end

--------------------------------------------------------------------------------
-- Interruptibility
--------------------------------------------------------------------------------

--- Digest a possibly-secret boolean into a plain {r, g, b} triple of (possibly
--- secret) components.
---
--- `notInterruptible` is SECRET on every unit that is not the player or their pet,
--- and a secret can be neither compared nor truth-tested. It cannot even be sieved
--- with type(): type() answers with the REAL type of a secret, so
--- `type(v) == "boolean"` PASSES for a secret bool and the `and v` that follows
--- immediately truth-tests it and throws. That reads like a secret check and is the
--- exact opposite of one -- it is the guard this function was written to remove.
---
--- C_CurveUtil.EvaluateColorFromBoolean resolves the branch inside the engine and
--- hands back a color instead of an answer, so the flag is never examined here at
--- all. It is SecretArguments = "AllowedWhenTainted"
--- (CurveUtilDocumentation.lua:31-47) and takes a plain bool just as happily, which
--- is why there is one path for the player and for a shielded boss rather than two.
---
--- The return is a ColorMixin table holding possibly-secret components: the TABLE
--- is plain, only its values are secret, so the field reads below are ordinary. The
--- consumers -- SetTextColor and SetColorTexture -- are both AllowedWhenTainted and
--- take secret components directly. Never compare an entry of the result.
local function PickColor(flag, whenTrue, whenFalse)
    local curve = C_CurveUtil
    local fn = curve and curve.EvaluateColorFromBoolean
    if fn then
        local ok, c = pcall(fn, flag,
            CreateColor(whenTrue[1], whenTrue[2], whenTrue[3], 1),
            CreateColor(whenFalse[1], whenFalse[2], whenFalse[3], 1))
        if ok and c then
            local gotFields, r, g, b = pcall(function() return c.r, c.g, c.b end)
            if gotFields and r ~= nil then return { r, g, b } end
        end

        -- Fallback: the per-component variant, which returns one secret number at a
        -- time and so cannot be defeated by the container being secret. Kept because
        -- it is the variant with a known production call site in a shipped
        -- cast bar; three calls instead of one, only on a state change.
        local vfn = curve.EvaluateColorValueFromBoolean
        if vfn then
            local okR, r = pcall(vfn, flag, whenTrue[1], whenFalse[1])
            local okG, g = pcall(vfn, flag, whenTrue[2], whenFalse[2])
            local okB, b = pcall(vfn, flag, whenTrue[3], whenFalse[3])
            if okR and okG and okB then return { r, g, b } end
        end
    end

    -- No engine helper at all. Comparing the flag is only safe once it is known to
    -- be plainly a boolean, which takes BOTH checks in this order -- type() first
    -- because it answers on secrets, issecretvalue() second because type() alone
    -- does not distinguish a secret bool from a real one.
    if type(flag) == "boolean" and not (issecretvalue and issecretvalue(flag)) then
        return flag and whenTrue or whenFalse
    end

    -- Unreadable and nothing to read it with. Draw it as interruptible: an
    -- uninterruptible cast shown as kickable wastes a kick, which is a smaller
    -- failure than an error thrown mid-cast.
    return whenFalse
end
-- Promoted for empowered.lua, which needs exactly this treatment per tier segment.
CBZ._PickColor = PickColor

--- Apply interruptibility to the line and, when tiers are up, to each segment.
---
--- Applied as a color override rather than by selecting a different palette,
--- because selecting anything would require reading the flag. The spell name is
--- deliberately not part of it -- see the band call at the end.
function CBZ._ApplyInterruptState(bar, notInterruptible)
    -- UnitCastingInfo returns nothing for this field on some casts. nil is never
    -- secret, and type() is the only test that is safe to run first.
    local ni = notInterruptible
    if type(ni) == "nil" then ni = false end

    -- Your own casts never take the locked treatment. The flag answers one
    -- question -- "can I kick this" -- and nobody kicks their own cast, so on
    -- player and pet it is information that cannot be acted on. It is not rare
    -- there either: Soar and the travel/mount-style casts all carry it, and
    -- honouring it strips the class-and-spec palette off ordinary casts and
    -- replaces it with white, which reads as the bar having lost its colors.
    -- frames.lua's _ResolveLineColor already documents this as the rule (":80-81",
    -- "the uninterruptible override never fires" on those units) -- it was written
    -- as a premise and never enforced. Enforced here, once, so the line
    -- and the bands cannot disagree about it.
    if CBZ.OWN_CAST_UNITS[bar.unitKey] then ni = false end

    -- Stashed so a settings change mid-cast can repaint at the right
    -- interruptibility instead of guessing. Holding a secret as a VALUE is safe;
    -- only a secret KEY poisons a table.
    bar.interruptFlag = ni

    local line = PickColor(ni, CBZ.LINE_COLOR_LOCKED, CBZ._GetLineColor(bar))
    -- No-op while tier segments are up -- they carry a palette, not one color.
    CBZ._ApplyLineColor(bar, line[1], line[2], line[3])
    -- ...and its counterpart, a no-op when they are not.
    CBZ._ApplyEmpoweredColors(bar, ni)

    -- The NAME takes no interruptibility override -- it keeps its ramp whatever the
    -- flag says. Interruptibility is the LINE's axis and it owns
    -- it outright: white for locked, gold for kickable, right behind the word.
    -- Draining the word to grey-white as well spent the bar's two channels saying
    -- one thing twice, and on a boss it read as the bar having lost its colors
    -- rather than as a cast you cannot kick -- the same misreading that took the
    -- override off player and pet above.
    CBZ._ApplyBandColors(bar, CBZ._GetRamp(bar))
end

--------------------------------------------------------------------------------
-- Progress handoff
--------------------------------------------------------------------------------

-- Hand the cast clock to the engine.
--
-- SetTimerDuration is annotated SecretArguments = "AllowedWhenUntainted", but
-- that annotation tests whether the ARGUMENT ITSELF is secret. A LuaDurationObject
-- is plain userdata that merely holds secrets internally, so the call is accepted
-- from addon context even on a restricted unit and the secrecy propagates into the
-- bar's value instead. Measured in-game. Do not gate this on
-- dur:HasSecretValues() -- it is informational, not a permission check.
--
-- Both duration getters are MayReturnNothing (UnitDocumentation.lua:798, 841), so
-- a missing return is a normal outcome, not an error.
--
-- Returns the duration object alongside the verdict so the cast time readout can
-- bind the SAME object the sweep was handed. Two getter calls would be two clocks,
-- and a number that disagreed with the bar underneath it about when the cast ends
-- is worse than no number at all.
local function ApplyDuration(bar, channelled)
    local unit = bar.unit
    local dur = channelled and UnitChannelDuration(unit) or UnitCastingDuration(unit)
    if not dur then return false end

    -- An empowered cast reports through UnitChannelInfo but does NOT drain: it
    -- charges, and the bar has to grow toward the tier you are aiming for.
    -- Blizzard models the same thing as reverseChanneling = true and counts up
    -- from the start time (CastingBarFrame.lua:446, 462-465). Phase 1 mapped every
    -- channel to RemainingTime, which ran empowered casts backwards.
    local drains = channelled and not bar.empowered
    local dir = drains and Enum.StatusBarTimerDirection.RemainingTime
                        or Enum.StatusBarTimerDirection.ElapsedTime

    -- interpolation is Nilable = false, Default = "Immediate"
    -- (SimpleStatusBarAPIDocumentation.lua:317) -- pass it explicitly.
    local ok = pcall(bar.progressBar.SetTimerDuration, bar.progressBar, dur,
        Enum.StatusBarInterpolation.Immediate, dir)
    return ok, dur
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function CancelPendingHide(bar)
    bar.hideToken = (bar.hideToken or 0) + 1
    -- Bumping the token stops Scoot's own timers, but UIFrameFadeOut handed the frame
    -- to Blizzard's fade manager, which keeps driving alpha down regardless.
    -- Without this the bar fades out underneath a cast that just started.
    UIFrameFadeRemoveFrame(bar)
    bar:SetAlpha(1)
    if bar.flashFrame then
        UIFrameFadeRemoveFrame(bar.flashFrame)
        bar.flashFrame:Hide()
    end
    -- Spam-casting starts the next cast while the previous one is still
    -- celebrating. Without this the new bar fills underneath the old bar's
    -- completion effect, which reads as the new cast having already landed.
    CBZ._StopFinishFX(bar)
    CBZ._RefreshSparkVisibility(bar)
end

function CBZ._StartCast(bar, channelled)
    local unit = bar.unit
    -- `_` declared local on purpose: the two return lists below discard six and
    -- seven fields respectively, and without this every one of those discards is a
    -- write to the global `_`.
    local _
    local name, notInterruptible, isEmpowered, numEmpowerStages

    if channelled then
        -- Return list: name, displayName, textureID, startTimeMs, endTimeMs,
        -- isTradeskill, notInterruptible, spellID, isEmpowered, numEmpowerStages,
        -- castBarID (UnitDocumentation.lua:869-879).
        name, _, _, _, _, _, notInterruptible, _, isEmpowered, numEmpowerStages =
            UnitChannelInfo(unit)
    else
        name, _, _, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
    end

    if type(name) == "nil" then
        CBZ._FinishCast(bar, nil)
        return
    end

    CancelPendingHide(bar)
    bar.casting = true
    bar.channelled = channelled

    -- isEmpowered and numEmpowerStages are the only two fields in the entire cast
    -- API annotated NeverSecret (UnitDocumentation.lua:877-878), so comparing them
    -- is safe on a shielded boss and a targeted Evoker alike. Everything Phase 3
    -- draws hangs off that one guarantee.
    bar.empowered = (channelled and isEmpowered == true) or false

    -- Resolve the palette once, here, and cache it for the life of the cast.
    -- Every consumer -- bands, spark, completion FX -- reads the cache, so the
    -- colors cannot shift under a bar mid-cast and the unit is queried once rather
    -- than once per band. It matters from Phase 2 step 4 on, where the ramp starts
    -- depending on WHO is casting: a bar that re-resolved per consumer would keep
    -- drawing the previous target's class colors after a switch.
    bar.lineColor, bar.ramp = CBZ._ResolveCastRamp(bar)

    -- The spark and the completion effect are colored by the layout pass, which
    -- runs on settings changes only -- so without this they would keep the palette
    -- of whoever this bar's unit was when the panel was last touched. Cheap: both
    -- reuse their existing regions rather than rebuilding.
    CBZ._RecolorSpark(bar)
    CBZ._RecolorFinishFX(bar)

    CBZ._SetText(bar, name)

    -- Before the colors, not after: _ApplyInterruptState routes to the tier
    -- palette or the single line color depending on whether segments are up, so
    -- the segments have to exist by the time it runs.
    CBZ._ApplyEmpowered(bar, bar.empowered, numEmpowerStages)
    CBZ._ApplyInterruptState(bar, notInterruptible)

    -- An empowered cast forces the spark on, and CancelPendingHide ran before
    -- bar.empowered was known.
    CBZ._RefreshSparkVisibility(bar)

    -- Park the sweep at its starting edge before handing over, so a duration that
    -- fails to resolve leaves an empty bar rather than a stale one. Empowered
    -- casts start empty like a normal cast, because they fill rather than drain.
    CBZ._SetStaticProgress(bar, (channelled and not bar.empowered) and 1 or 0)
    bar:Show()

    -- Target/Focus/Boss suppression is alpha-based (their spell bars cannot be
    -- re-parented), and Blizzard restores its own alpha from this same event.
    -- No-op for the parked Player and Pet bars.
    CBZ._ReassertSuppression(bar.barKey)

    local applied, dur = ApplyDuration(bar, channelled)
    if applied then
        -- An empowered cast counts UP whatever the readout setting says, matching
        -- its fill; casttime.lua owns that override.
        CBZ._StartCastTime(bar, dur, bar.empowered)
    else
        -- Not expected: measured working on plain and secret durations alike.
        -- Show the name on a static bar rather than an animating lie.
        CBZ._SetStaticProgress(bar, (channelled and not bar.empowered) and 1 or 0)
        -- ...and no number, rather than one frozen at whatever the last cast left.
        CBZ._StopCastTime(bar)
    end
end

--- Re-read the clock after pushback or a channel tick change.
function CBZ._RefreshCast(bar)
    if not bar.casting then return end
    local applied, dur = ApplyDuration(bar, bar.channelled)
    if applied then
        CBZ._RefreshCastTime(bar, dur)
    end
end

--- Swap the bar into its interrupted / failed look.
---
--- Blizzard snaps its bar to the "full" art on interrupt (CastingBarFrame.lua:239)
--- so the word reads across the whole bar. Z does the same by snapping the reveal
--- to full width — a half-lit "Interrupted" would just look like a rendering fault.
local function ShowFailureState(bar, reason)
    -- The safety net under _QueueFinishFX's one-frame delay. If the STOP and the
    -- INTERRUPTED ever land more than a frame apart, the success effect will have
    -- started; killing it here means the worst case is a single frame of the wrong
    -- color rather than a flourish that visibly turns red.
    CBZ._StopFinishFX(bar)

    -- Tier segments come down FIRST. A failed cast reads as one red bar end to
    -- end, and leaving them up would both stripe that red and silently swallow
    -- the _ApplyLineColor below, which refuses to write while tiers are active.
    CBZ._ClearEmpowered(bar)

    CBZ._SetStaticProgress(bar, 1)
    CBZ._SetText(bar, reason)

    local flat = {}
    for i = 1, CBZ.NUM_BANDS do flat[i] = FAIL_TEXT_COLOR end
    CBZ._ApplyBandColors(bar, flat)
    CBZ._ApplyLineColor(bar, FAIL_LINE_COLOR[1], FAIL_LINE_COLOR[2], FAIL_LINE_COLOR[3])

    local flash = bar.flashFrame
    if flash then
        UIFrameFadeRemoveFrame(flash)
        local peak = flash.peakAlpha or 1
        flash:SetAlpha(peak)
        flash:Show()
        UIFrameFadeOut(flash, FLASH_TIME, peak, 0)
    end
end

--- @param reason string|nil  INTERRUPTED / FAILED for a failure, nil for a clean end.
function CBZ._FinishCast(bar, reason)
    if not bar.casting and not bar:IsShown() then return end

    -- A cast resolves once, but it can report itself more than once: an interrupted
    -- cast fires both a plain STOP and an INTERRUPTED, in an order that is not
    -- guaranteed. A trailing FAILURE is let through, because "Interrupted" is the
    -- more informative of the two readings and should win. A trailing CLEAN stop is
    -- not: it would reset the failure's progress and cut its hold from HOLD_FAILED
    -- back to the shorter HOLD_COMPLETE.
    --
    -- This also subsumes the old snapshot-bar.casting gate. _FinishCast(bar, nil) is
    -- the bail-out path for a cast that never resolved (_StartCast, name == nil);
    -- with the flag already clear, that call now returns here rather than
    -- celebrating a cast that never happened.
    if not bar.casting and not reason then return end

    local wasChannel = bar.channelled
    local wasEmpowered = bar.empowered
    bar.casting = false
    bar.channelled = false
    bar.empowered = false

    if CBZ._editModeActive then
        -- Edit Mode keeps the bar parked and visible for positioning.
        CBZ._ShowEditModePreview(bar)
        return
    end

    -- The spark marks where the cast is right now; once it has ended there is no
    -- "right now". Left up, it snaps to whichever edge the fill was just parked at
    -- and sits there through the hold, which reads as a cast still in flight --
    -- exactly the complaint against a bar frozen at full. Blizzard hides it too
    -- (CastingBarFrame.lua:580), differing only in flashing a red pip on interrupt
    -- first, which Z deliberately skips.
    CBZ._SetSparkShown(bar, false)

    -- Same argument, and Blizzard hides its own readout here too
    -- (UpdateCastTimeTextShown gates on `casting or channeling`, :749-759). It also
    -- sidesteps an edge the binding would otherwise expose: a duration can expire a
    -- frame or two before its STOP arrives, and an expired binding writes its
    -- expired text over whatever the cast finished on. Before the branch below, so
    -- it covers a clean end, a failure and an empowered freeze alike.
    CBZ._StopCastTime(bar)

    -- Take the clock back from the engine. SetTimerDuration hands the sweep to
    -- C++ and nothing else ever stops it: without this the fill keeps advancing
    -- through the hold, so an interrupt at 40% finishes filling and reads as a
    -- cast that completed normally. SetValue overrides the running timer.
    if reason then
        ShowFailureState(bar, reason)
    elseif wasEmpowered then
        -- Freeze, do not park. An empowered cast ends when the player releases,
        -- and where they released is the entire result of the cast: snapping to
        -- full claims max tier, snapping to empty claims none. Both are wrong
        -- almost every time.
        CBZ._FreezeProgress(bar)
    else
        CBZ._SetStaticProgress(bar, wasChannel and 0 or 1)
    end

    bar.hideToken = (bar.hideToken or 0) + 1
    local token = bar.hideToken
    local hold = reason and HOLD_FAILED or HOLD_COMPLETE

    -- Queued rather than played, and only after the token bump above, so that an
    -- interrupt arriving later in the same frame invalidates it. See
    -- CBZ._QueueFinishFX.
    if not reason then
        CBZ._QueueFinishFX(bar)
    end

    C_Timer.After(hold, function()
        if bar.hideToken ~= token then return end
        UIFrameFadeOut(bar, FADE_TIME, 1, 0)
        C_Timer.After(FADE_TIME, function()
            if bar.hideToken ~= token then return end
            bar:Hide()
            bar:SetAlpha(1)
            CBZ._ClearText(bar)
            CBZ._ClearCastPalette(bar)
            -- After the frame is hidden, so the plain line coming back is never
            -- seen. Before the next cast, so nothing inherits a tier palette.
            CBZ._ClearEmpowered(bar)
            CBZ._SetStaticProgress(bar, 0)
            CBZ._StopFinishFX(bar)
            if bar.flashFrame then
                UIFrameFadeRemoveFrame(bar.flashFrame)
                bar.flashFrame:Hide()
            end
        end)
    end)
end

--- A STOP / FAILED / INTERRUPTED can arrive for a cast that has already been
--- superseded -- spam-casting produces exactly this, and acting on it would hide a
--- bar that should still be running.
---
--- Blizzard disambiguates by comparing castID against the one it stored. That does
--- not generalise: castID is a WOWGUID and is secret on any restricted unit, so it
--- cannot be compared at all in Phase 2. Asking the unit what it is doing right now
--- costs one API call and works everywhere.
--- Re-querying is also what keeps an unrelated failure from killing a live cast:
--- mash an instant while a long cast is running and its UNIT_SPELLCAST_FAILED
--- arrives here, but the unit is still casting, so the bar carries on.
local function ResolveStop(bar, reason)
    local channelling = IsChannelling(bar.unit)
    local superseded = channelling or IsCasting(bar.unit)

    if superseded then
        -- The cast this event belongs to still ended, and if it ended cleanly it
        -- earned its flourish. Queueing the next spell is not a reason to swallow
        -- the last one's completion -- spam-casting is the case where you most
        -- want the confirmation, because the bar refilling looks identical whether
        -- the previous cast landed or was eaten.
        --
        -- Order is load-bearing. bar.casting has to be read before _StartCast,
        -- which sets it for the NEW cast; and the play has to come after, because
        -- _StartCast calls CancelPendingHide, which stops any effect in flight.
        local completed = (reason == nil) and bar.casting
        CBZ._StartCast(bar, channelling)
        if completed then
            -- Queued for the same reason as in _FinishCast: a STOP that turns out
            -- to have been an interrupt must not get its flourish in first.
            -- _StartCast has just bumped the token via CancelPendingHide, so the
            -- queued play is invalidated by anything that resolves the bar again.
            CBZ._QueueFinishFX(bar)
        end
        return
    end

    CBZ._FinishCast(bar, reason)
end

--- Collect the events that describe one ending cast, and resolve them together a
--- frame later.
---
--- **Nothing about the end of a cast is decidable at the instant one event
--- arrives.** A cancelled cast reports itself twice — an `INTERRUPTED` (or
--- `FAILED`) and a plain `STOP` — and `UnitCastingInfo` can still be answering for
--- the cast that just ended when the first of them lands. Resolving inline makes
--- the outcome depend on which report won the race, and the losing orderings are
--- not merely cosmetic: a cancelled cast opened with the success flourish and then
--- turned red, and the interrupt could be swallowed entirely by the supersede
--- branch when `UnitCastingInfo` had not yet caught up.
---
--- Blizzard sidesteps all of this by comparing `castID` against the one it stored
--- and by branching on its own cached `casting` flag rather than re-querying
--- (`CastingBarMixin:HandleCastStop`). Z cannot: `castID` is a WOWGUID and is
--- secret on any restricted unit, which is the whole reason the re-query exists.
---
--- So no event resolves anything. Each one records what it knows, and a single
--- deferred pass decides — by which time the client has settled and the reports
--- have all arrived. A failure reason outranks a clean stop, because "Interrupted"
--- is the more informative reading of the same cast.
local function HandleStop(bar, reason)
    if reason then bar.pendingReason = reason end

    if bar.pendingStop then return end
    bar.pendingStop = true

    C_Timer.After(0, function()
        bar.pendingStop = nil
        local pending = bar.pendingReason
        bar.pendingReason = nil
        ResolveStop(bar, pending)
    end)
end

--------------------------------------------------------------------------------
-- Event routing
--------------------------------------------------------------------------------

--- Did a channel / empower stop event describe a cast that did NOT go off?
---
--- Neither reports failure through UNIT_SPELLCAST_INTERRUPTED. Blizzard gates that
--- handler on `self.casting` (CastingBarFrame.lua:235), which is nil for both, and
--- reads the outcome off the stop event's own payload instead (:266-274). So a
--- Fire Breath cancelled by moving arrives as a plain EMPOWER_STOP and nothing
--- anywhere else ever says it failed -- which is exactly how Z came to draw a
--- cancelled empower as a clean release.
---
--- Two signals, because each answers where the other cannot:
---
--- * `complete` is authoritative and is PLAIN on the player, the only place a
---   self-cancel is recorded at all. It is secret on any restricted unit -- the
---   whole event is SecretWhenUnitSpellCastRestricted and `complete` carries no
---   NeverSecret of its own (UnitDocumentation.lua:4501-4516) -- so it is tested
---   plainly-false: type() first because it answers on secrets, issecretvalue()
---   second because type() alone cannot tell a secret bool from a real one.
---
--- * `interruptedBy` is a GUID and is likewise secret when restricted, but its
---   ABSENCE is nil, and nil is never secret. So "did somebody kick this" stays
---   answerable on a targeted Evoker even though "did they release it" does not.
---   This is the only field on either stop event that survives the restriction.
---
--- The remaining gap is exact and worth naming rather than papering over: a
--- restricted unit's SELF-cancelled empower cannot be told from a released one.
--- It renders as a freeze -- the honest reading of what is visible.
local function StopWasFailure(complete, interruptedBy)
    if type(interruptedBy) ~= "nil" then return true end
    if type(complete) ~= "boolean" then return false end
    if issecretvalue and issecretvalue(complete) then return false end
    return complete == false
end

function CBZ._OnCastEvent(barKey, event, ...)
    local bar = CBZ._bars[barKey]
    if not bar then return end
    if not CBZ._IsUnitEnabled(bar.unitKey) then return end

    if event == "UNIT_SPELLCAST_START" then
        CBZ._StartCast(bar, false)

    elseif event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
        -- Empowered casts render as channels in Phase 1; Phase 3 adds tier
        -- segments and pip dividers on top of the same sweep.
        CBZ._StartCast(bar, true)

    elseif event == "UNIT_SPELLCAST_DELAYED"
        or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        CBZ._RefreshCast(bar)

    elseif event == "UNIT_SPELLCAST_STOP" then
        -- A plain cast that fails reports it separately, below.
        HandleStop(bar, nil)

    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- Payload: unitTarget, castGUID, spellID, interruptedBy
        -- (UnitDocumentation.lua:4444-4458). Blizzard derives the same verdict as
        -- `interruptedBy == nil` (CastingBarFrame.lua:378).
        local interruptedBy = select(4, ...)
        HandleStop(bar, StopWasFailure(nil, interruptedBy) and INTERRUPTED or nil)

    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        -- Payload: unitTarget, castGUID, spellID, complete, interruptedBy
        -- (UnitDocumentation.lua:4501-4516). `complete` is the field that makes a
        -- moved-out-of empower distinguishable from a released one.
        local complete, interruptedBy = select(4, ...)
        HandleStop(bar, StopWasFailure(complete, interruptedBy) and INTERRUPTED or nil)

    -- Same split Blizzard uses (CastingBarFrame.lua:244-249): FAILED reads
    -- "Failed", everything else reads "Interrupted". Both are global strings, so
    -- both are plain text on every unit.
    elseif event == "UNIT_SPELLCAST_FAILED" then
        HandleStop(bar, FAILED)

    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        HandleStop(bar, INTERRUPTED)

    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        CBZ._ApplyInterruptState(bar, false)

    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        CBZ._ApplyInterruptState(bar, true)
    end
end

--- Pick up a cast that was already in flight when the bar came online (login,
--- /reload, a target switch, or the user enabling the unit mid-cast).
function CBZ._SyncCastState(barKey)
    local bar = CBZ._bars[barKey]
    if not bar or not CBZ._IsUnitEnabled(bar.unitKey) then return end

    if IsChannelling(bar.unit) then
        CBZ._StartCast(bar, true)
    elseif IsCasting(bar.unit) then
        CBZ._StartCast(bar, false)
    end
end

--- Wipe the bar instantly: no hold, no fade, nothing carried over.
---
--- A departed target's bar is not a cast that ended, it is a cast that stopped
--- being this bar's business. Routing it through _FinishCast would hold the
--- previous target's spell name on screen for HOLD + FADE, straight over the new
--- target's cast if one starts inside that window -- and on a secret unit that name
--- cannot even be inspected to notice. Blizzard resets rather than finishes for the
--- same reason (TargetSpellBarMixin:OnEvent's else-branch, TargetFrame.lua:1077-1084).
function CBZ._ResetBar(bar)
    -- Bumping the token invalidates everything already scheduled against this bar:
    -- the hold, the fade, and any queued completion FX.
    bar.hideToken = (bar.hideToken or 0) + 1
    bar.casting = false
    bar.channelled = false
    bar.empowered = false
    bar.pendingStop = nil
    bar.pendingReason = nil

    UIFrameFadeRemoveFrame(bar)
    bar:SetAlpha(1)
    CBZ._StopFinishFX(bar)
    if bar.flashFrame then
        UIFrameFadeRemoveFrame(bar.flashFrame)
        bar.flashFrame:Hide()
    end

    CBZ._ClearText(bar)
    CBZ._ClearCastPalette(bar)
    CBZ._ClearEmpowered(bar)
    CBZ._StopCastTime(bar)
    CBZ._SetStaticProgress(bar, 0)

    -- Edit Mode is positioning this frame; taking it away mid-drag would be a bug,
    -- not a reset. Put the stand-in back instead.
    if CBZ._editModeActive and CBZ._IsUnitEnabled(bar.unitKey) then
        CBZ._ShowEditModePreview(bar)
    else
        bar:Hide()
    end
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

--- One event frame per BAR, created with the bar itself.
---
--- Per-bar rather than shared: RegisterUnitEvent accepts at most two unit tokens,
--- and five boss bars need five. It also keeps routing free of a filter test on
--- every event.
function CBZ._RegisterBarEvents(bar, row)
    if bar.eventFrame then return end

    local f = CreateFrame("Frame")
    for _, ev in ipairs(CAST_EVENTS) do
        f:RegisterUnitEvent(ev, row.token)
    end

    -- Most unit-change events are NOT unit events -- PLAYER_TARGET_CHANGED and
    -- INSTANCE_ENCOUNTER_ENGAGE_UNIT carry no unit argument at all -- so they take a
    -- plain RegisterEvent on the same frame. Mixing the two registration styles on
    -- one frame is fine; mixing them for the same event is not.
    --
    -- UNIT_PET is the exception: it IS a unit event, but its argument is the pet's
    -- owner rather than the pet, so it filters on changeEventUnit instead of token.
    if row.changeEvent then
        if row.changeEventUnit then
            f:RegisterUnitEvent(row.changeEvent, row.changeEventUnit)
        else
            f:RegisterEvent(row.changeEvent)
        end
    end

    -- The payload is forwarded, not dropped: a channel or empower that ended badly
    -- says so in its own arguments and nowhere else. See StopWasFailure.
    f:SetScript("OnEvent", function(_, event, ...)
        if event == row.changeEvent then
            -- Coalesced into one deferred pass for the same reason cast-end is: the
            -- client has not necessarily settled at the instant the event fires, and
            -- UnitCastingInfo can still be answering for the unit just left.
            CBZ._ResetBar(bar)
            C_Timer.After(0, function()
                CBZ._SyncCastState(row.barKey)
            end)
            return
        end
        CBZ._OnCastEvent(row.barKey, event, ...)
    end)

    bar.eventFrame = f
end

function CBZ._InitializeEvents(comp)
    -- Spec changes re-resolve the ramp; talent swaps do not, but a spec swap is
    -- the only thing that moves SPEC_GRADIENT_COLORS.
    -- Registered once (_Initialize latches), so the file-scoped owner keeps the
    -- handlers alive across component re-initialization.
    local function onSpecEvent(event)
        if event == "PLAYER_ENTERING_WORLD" then
            -- Catches a Blizzard bar that did not exist when Z first reconciled,
            -- and any alpha reset across the loading screen.
            CBZ._ReassertAllSuppression()
        end

        for barKey, bar in pairs(CBZ._bars) do
            if CBZ._IsUnitEnabled(bar.unitKey) then
                -- Drop the cache first, or the repaint reads back the very palette
                -- the spec change just invalidated.
                CBZ._ClearCastPalette(bar)
                CBZ._ApplyBandColors(bar, nil)
                if event == "PLAYER_ENTERING_WORLD" then
                    CBZ._SyncCastState(barKey)
                end
            end
        end
    end
    addon.Events.On("CastBarZ:Spec", "PLAYER_SPECIALIZATION_CHANGED", onSpecEvent)
    addon.Events.On("CastBarZ:Spec", "PLAYER_ENTERING_WORLD", onSpecEvent)
end
