--------------------------------------------------------------------------------
-- bars/combat.lua
-- Combat deferral for unit frame bar styling
-- Queues operations that cannot be performed during combat lockdown onto the
-- shared regen drain (Events.RunOutOfCombat), keyed so repeat queues for the
-- same target coalesce to one apply.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Create module namespace
addon.BarsCombat = addon.BarsCombat or {}
local Combat = addon.BarsCombat

--------------------------------------------------------------------------------
-- Power Bar / Unit Frame Texture Combat Deferral
--------------------------------------------------------------------------------
-- Both drain through ApplyUnitFrameBarTexturesFor but keep separate key
-- namespaces: a unit queued into both runs the apply twice, as the two
-- watcher frames always did.

-- ApplyUnitFrameBarTexturesFor handles full styling including custom positioning
local function applyBarTexturesFor(unit)
    if addon.ApplyUnitFrameBarTexturesFor then
        addon.ApplyUnitFrameBarTexturesFor(unit)
    end
end

function Combat.queuePowerBarReapply(unit)
    addon.Events.RunOutOfCombat(function()
        applyBarTexturesFor(unit)
    end, "BarsCombat:power:" .. unit)
end

function Combat.queueUnitFrameTextureReapply(unit)
    addon.Events.RunOutOfCombat(function()
        applyBarTexturesFor(unit)
    end, "BarsCombat:texture:" .. unit)
end

--------------------------------------------------------------------------------
-- Raid/Party Frame Combat Deferral
--------------------------------------------------------------------------------
-- CompactUnitFrame (raid/party) cosmetic changes must NEVER be applied during combat,
-- and synchronous work inside Blizzard's CompactUnitFrame update chains must be avoided.

-- The drains run the same chains ApplyStyles runs (core/refresh.lua), so the
-- post-combat state matches the out-of-combat state.
local function applyRaidFrameStyles()
    addon.Refresh.Run("raid")
end

local function applyPartyFrameStyles()
    addon.Refresh.Run("party")
end

function Combat.queueRaidFrameReapply()
    addon.Events.RunOutOfCombat(applyRaidFrameStyles, "BarsCombat:raid")
end

function Combat.queuePartyFrameReapply()
    addon.Events.RunOutOfCombat(applyPartyFrameStyles, "BarsCombat:party")
end

return Combat
