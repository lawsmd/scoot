--------------------------------------------------------------------------------
-- unitframesz/suppression.lua
-- Taking Blizzard's own unit frame off screen for any unit Frame Z draws.
--
-- There is no setting for this. X and Z are exclusive per unit (the Features
-- page mode cycle), so choosing Z leaves Blizzard's frame unstyled AND on
-- screen -- two frames for one unit. A duplicate of the thing Z was turned on
-- to replace is not a preference.
--
-- The mechanism lives in core/nativeframe.lua -- a hidden parent, refcounted
-- per owner. This file only decides WHICH frames Z currently owns. Both
-- PlayerFrame and TargetFrame are top-level Edit Mode system frames, so both
-- take the "park" method (nativeframe.lua's rule of thumb: park top-level
-- frames, dim children of a system); their green selection outlines are
-- handled by NativeFrame's ApplySelection.
--
-- Parking hides the WHOLE subtree, and Blizzard parents more under these
-- frames than the frames themselves (accepted; the
-- Features-page Z tooltips name the casualties):
--   PlayerFrame  -> PetFrame, TotemFrame, RuneFrame, ClassPowerBarFrame, and
--                   PlayerCastingBarFrame while Edit Mode's "Lock to Player
--                   Frame" is on (PlayerFrame.lua:40)
--   TargetFrame  -> TargetFrameToT, TargetFrameSpellBar
--   FocusFrame   -> FocusFrameToT, FocusFrameSpellBar
--   BossTargetFrameContainer -> all five Boss<N>TargetFrame and their spell bars
-- Those children come back the moment the unit leaves Z mode; their own Z
-- equivalents are future components (Cast Bar Z already covers the boss bars).
--
-- The target-of-target frame is the one child Z owns directly. It goes with
-- TargetFrame whenever Target is Z; with Target on X or OFF it is dimmed on
-- its own, because a child of a system frame is never parked (its parent's
-- layout code reads it). Blizzard never writes alpha on it, so the dim needs
-- no per-event re-assert, and Dim is a deferred SetAlpha, legal in combat.
--------------------------------------------------------------------------------

local addonName, addon = ...
local UFZ = addon.UnitFramesZ

local OWNER = "unitFramesZ"

-- Names are Blizzard's own, read out of the source rather than derived:
-- PlayerFrame (PlayerFrame.xml), TargetFrame and BossTargetFrameContainer
-- (TargetFrame.xml:708).
--
-- Boss parks the CONTAINER, not the five frames inside it. That is the whole
-- decision and it is not interchangeable: BossTargetFrameContainer is a
-- VerticalLayoutFrame whose UpdateSize() walks self.BossTargetFrames and calls
-- Layout() on their sizes, so re-parenting the children out from under it
-- breaks its layout code. Parking the container and leaving the children
-- alone is the shape that holds; parking the children instead is what breaks
-- it. It is also one
-- call instead of five, and it matches nativeframe.lua's own rule of thumb:
-- park top-level frames, dim children of a system.
--
-- Blizzard re-parents this container to UIParent on EVERY Edit Mode enter and
-- exit, so NativeFrame's deferred SetParent re-park hook is load-bearing here
-- rather than belt-and-braces.
--
-- The same re-parent happens on every Edit Mode layout pass
-- (ApplySystemAnchor -> BreakFromFrameManager, EditModeSystemTemplates.lua:343),
-- and that pass can run in combat, where the re-park waits for
-- PLAYER_REGEN_ENABLED. So the Boss claim carries a quiet list: the events that
-- show a boss frame, silenced while the container is parked, and a Hide for any
-- boss frame already shown. A boss frame with no show events stays hidden
-- wherever the container goes.
--   BossTargetFrameContainer  PLAYER_ENTERING_WORLD -> UpdateShownState, which
--                             shows each boss frame whose unit exists
--                             (TargetFrame.lua:1053-1057,
--                             EditModeSystemTemplates.lua:1642-1652)
--   Boss<N>TargetFrame        PLAYER_ENTERING_WORLD and UNIT_TARGETABLE_CHANGED
--                             -> Update; on Boss1 also
--                             INSTANCE_ENCOUNTER_ENGAGE_UNIT, which updates all
--                             five (TargetFrame.lua:161-191, 962, 1008)
-- Their other events repaint without showing. Edit Mode enter and exit still
-- show the frames (RefreshBossFrames, EditModeManager.lua:2379); the Reapply on
-- exit hides them again. The container is not hidden: with its children hidden
-- it draws nothing.
--
-- Player, Target and Focus need no list. They are not frame-manager frames, so
-- the layout pass never re-parents them.
local BOSS_CONTAINER_EVENTS = { "PLAYER_ENTERING_WORLD" }
local BOSS_FRAME_EVENTS = {
    "PLAYER_ENTERING_WORLD", "UNIT_TARGETABLE_CHANGED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
}

local function QuietBossFrames(container)
    local quiet = { { frame = container, events = BOSS_CONTAINER_EVENTS } }
    for i = 1, UFZ.NUM_BOSS_FRAMES do
        local bossFrame = _G["Boss" .. i .. "TargetFrame"]
        if bossFrame then
            quiet[#quiet + 1] = { frame = bossFrame, events = BOSS_FRAME_EVENTS, hide = true }
        end
    end
    return quiet
end

local BLIZZARD_FRAME = {
    Player         = { name = "PlayerFrame", method = "park" },
    Target         = { name = "TargetFrame", method = "park" },
    Focus          = { name = "FocusFrame", method = "park" },
    TargetOfTarget = { name = "TargetFrameToT", method = "alpha" },
    Boss           = { name = "BossTargetFrameContainer", method = "park", quiet = QuietBossFrames },
}

-- Which frames Z currently owns. Nothing is ever released that was not
-- suppressed first: zero-touch means a profile that never enabled Z must not
-- see this file touch a Blizzard frame in either direction.
local suppressed = {}

local function ResolveFrame(unitKey)
    local row = BLIZZARD_FRAME[unitKey]
    return row and _G[row.name] or nil
end

--- Re-assert every claim Z currently holds.
---
--- Called on Edit Mode enter and exit. Both matter: NativeFrame skips the
--- re-parent while the Edit Mode manager is open (writing there taints the
--- manager, not just the frame -- see nativeframe.lua), so entering Edit Mode
--- is where a claim gets deferred and leaving it is where it gets paid.
function UFZ._ReassertAllSuppression()
    if not next(suppressed) then return end
    addon.NativeFrame:Reapply()
end

--- Reconcile every Blizzard unit frame against what Z is currently drawing.
---
--- Writes only on a TRANSITION. _ApplyStyling runs on every settings change --
--- including every step of the Edit Mode Scale slider -- and re-issuing claims
--- per step would be pure churn for a state that has not moved.
function UFZ._ApplySuppression()
    local moduleOn = addon:IsModuleEnabled("unitFramesZ")

    for _, unitKey in ipairs(UFZ.UNITS) do
        local want = (moduleOn
            and UFZ._IsUnitEnabled(unitKey)
            and BLIZZARD_FRAME[unitKey] ~= nil) or false

        if want ~= (suppressed[unitKey] == true) then
            local frame = ResolveFrame(unitKey)
            if frame then
                if want then
                    local row = BLIZZARD_FRAME[unitKey]
                    addon.NativeFrame:Suppress(frame, OWNER, row.method, row.quiet and row.quiet(frame))
                else
                    addon.NativeFrame:Release(frame, OWNER)
                end
            end
            suppressed[unitKey] = want or nil
        end
    end
end
