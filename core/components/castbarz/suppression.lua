--------------------------------------------------------------------------------
-- castbarz/suppression.lua
-- Taking Blizzard's own cast bar off screen for any unit Cast Bar Z draws.
--
-- There is no setting for this. Cast Bar X and Cast Bar Z are mutually exclusive
-- (modules.lua), so choosing Z leaves Blizzard's bars unstyled AND on screen --
-- two bars for one spell. A duplicate of the thing Z was turned on to replace is
-- not a preference.
--
-- Suppression is per BAR, not per unit config, so enabling Boss hides all five of
-- Blizzard's boss spell bars while a Pet bar left off keeps its own.
--
-- The mechanism lives in core/nativeframe.lua -- a hidden parent, refcounted per
-- owner. This file only decides WHICH bars Z currently owns. An earlier build
-- used SetAlpha(0) here instead; that lost to Blizzard's Edit Mode force-show
-- (CastingBarFrame.lua:84-90, ApplyAlpha(1.0) whenever isInEditMode is set) and
-- could never touch the green selection outline, which is ignoreParentAlpha by
-- design. A hidden parent has neither problem: it removes the subtree from the
-- render tree instead of arguing with it about opacity.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CBZ = addon.CastBarZ

local OWNER = "castBarZ"

-- One Blizzard frame per bar. Names are Blizzard's own, read out of the source
-- rather than derived: PlayerCastingBarFrame (CastingBarFrame.xml), the spell
-- bars TargetFrame:CreateSpellbar builds as "<parent name>SpellBar"
-- (TargetFrame.lua:968), and PetCastingBarFrame (PetFrame.xml:190).
--
-- Pet IS listed, correcting the plan. Blizzard's pet bar shows only while
-- UnitIsPossessed("pet") (PetFrame.lua:180, 187), which is rare enough that the
-- plan wrote it off as "nothing to suppress" -- but rare is not never, and during
-- a possession Z draws the same cast. One table entry closes it.
--
-- The method split is not a preference. Player and Pet are top-level frames and
-- get parked. The spell bars CANNOT be: TargetSpellBarMixin:AdjustPosition reads
-- `parentFrame.auraRows > 2` (TargetFrame.lua:1097) and BossSpellBarMixin indexes
-- `self:GetParent().powerBarAlt` (:1115), so re-parenting them throws from inside
-- Blizzard's own OnEvent the first time Edit Mode targets something. They take
-- alpha, which is weaker -- hence _ReassertSuppression below.
local BLIZZARD_BAR = {
    Player = { name = "PlayerCastingBarFrame", method = "park" },
    Pet    = { name = "PetCastingBarFrame",    method = "park" },
    Target = { name = "TargetFrameSpellBar",   method = "alpha" },
    Focus  = { name = "FocusFrameSpellBar",    method = "alpha" },
}
for i = 1, CBZ.NUM_BOSS_BARS do
    BLIZZARD_BAR["Boss" .. i] = {
        name = "Boss" .. i .. "TargetFrameSpellBar", method = "alpha",
    }
end

-- Which bars Z currently owns. Nothing is ever released that was not suppressed
-- first: zero-touch means a profile that never enabled Z must not see this file
-- touch a Blizzard frame in either direction.
local suppressed = {}

local function ResolveFrame(barKey)
    local row = BLIZZARD_BAR[barKey]
    return row and _G[row.name] or nil
end

--- Re-hide one Blizzard bar that has just un-hidden itself.
---
--- Only does anything for the alpha-method bars: Blizzard drives its own
--- ApplyAlpha(1.0) off the cast-start path, so those need re-asserting once per
--- cast. A parked frame ignores alpha entirely and falls through harmlessly.
--- Called from _StartCast, so one seam covers casts, channels and empowers.
function CBZ._ReassertSuppression(barKey)
    if not suppressed[barKey] then return end
    local frame = ResolveFrame(barKey)
    if frame then addon.NativeFrame:Reapply(frame) end
end

--- Re-assert every claim Z currently holds.
---
--- Called on Edit Mode enter and exit. Both matter: Blizzard skips our re-parent
--- while the Edit Mode manager is open (writing there taints the manager, not just
--- the frame -- see nativeframe.lua), so entering Edit Mode is where a claim gets
--- deferred and leaving it is where the deferred claim gets paid.
function CBZ._ReassertAllSuppression()
    if not next(suppressed) then return end
    addon.NativeFrame:Reapply()
end

--- Reconcile every Blizzard bar against what Z is currently drawing.
---
--- Writes only on a TRANSITION. _ApplyStyling runs on every settings change --
--- including every step of an offset slider drag through the Edit Mode mirror --
--- and re-issuing nine claims per step would be pure churn for a state that has
--- not moved.
function CBZ._ApplySuppression()
    local moduleOn = addon:IsModuleEnabled("castBars", "castBarZ")

    for _, row in ipairs(CBZ.BARS) do
        local barKey = row.barKey
        local want = (moduleOn
            and CBZ._IsUnitEnabled(row.unitKey)
            and BLIZZARD_BAR[barKey] ~= nil) or false

        if want ~= (suppressed[barKey] == true) then
            local frame = ResolveFrame(barKey)
            if frame then
                if want then
                    addon.NativeFrame:Suppress(frame, OWNER, BLIZZARD_BAR[barKey].method)
                else
                    addon.NativeFrame:Release(frame, OWNER)
                end
            end
            suppressed[barKey] = want or nil
        end
    end
end
