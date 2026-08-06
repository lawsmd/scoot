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
-- frames than the frames themselves (accepted, user decision 2026-08-05; the
-- Features-page Z tooltips name the casualties):
--   PlayerFrame  -> PetFrame, TotemFrame, RuneFrame, ClassPowerBarFrame, and
--                   PlayerCastingBarFrame while Edit Mode's "Lock to Player
--                   Frame" is on (PlayerFrame.lua:40)
--   TargetFrame  -> TargetFrameToT, TargetFrameSpellBar
-- Those children come back the moment the unit leaves Z mode; their own Z
-- equivalents are future components.
--------------------------------------------------------------------------------

local addonName, addon = ...
local UFZ = addon.UnitFramesZ

local OWNER = "unitFramesZ"

-- Names are Blizzard's own, read out of the source rather than derived:
-- PlayerFrame (PlayerFrame.xml), TargetFrame (TargetFrame.xml).
local BLIZZARD_FRAME = {
    Player = { name = "PlayerFrame", method = "park" },
    Target = { name = "TargetFrame", method = "park" },
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
--- Called on Edit Mode enter and exit. Both matter: NativeFrame skips our
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
                    addon.NativeFrame:Suppress(frame, OWNER, BLIZZARD_FRAME[unitKey].method)
                else
                    addon.NativeFrame:Release(frame, OWNER)
                end
            end
            suppressed[unitKey] = want or nil
        end
    end
end
