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

local function applyRaidFrameStyles()
    if addon.ApplyRaidFrameHealthBarStyle then
        addon.ApplyRaidFrameHealthBarStyle()
    end
    if addon.ApplyRaidFrameStatusTextStyle then
        addon.ApplyRaidFrameStatusTextStyle()
    end
    if addon.ApplyRaidFrameGroupTitlesStyle then
        addon.ApplyRaidFrameGroupTitlesStyle()
    end
    -- Also apply combat-safe overlays (create/update overlays out of combat)
    if addon.ApplyRaidFrameHealthOverlays then
        addon.ApplyRaidFrameHealthOverlays()
    end
    if addon.ApplyRaidFrameNameOverlays then
        addon.ApplyRaidFrameNameOverlays()
    end
    -- Apply health bar borders
    if addon.ApplyRaidFrameHealthBarBorders then
        addon.ApplyRaidFrameHealthBarBorders()
    end
    -- Apply visibility settings
    if addon.ApplyRaidOverAbsorbGlowVisibility then
        addon.ApplyRaidOverAbsorbGlowVisibility()
    end
    if addon.ApplyRaidHealPredictionVisibility then
        addon.ApplyRaidHealPredictionVisibility()
    end
    if addon.ApplyRaidAbsorbBarsVisibility then
        addon.ApplyRaidAbsorbBarsVisibility()
    end
    if addon.ApplyRaidHealPredictionClipping then
        addon.ApplyRaidHealPredictionClipping()
    end
end

local function applyPartyFrameStyles()
    if addon.ApplyPartyFrameHealthBarStyle then
        addon.ApplyPartyFrameHealthBarStyle()
    end
    if addon.ApplyPartyFrameTitleStyle then
        addon.ApplyPartyFrameTitleStyle()
    end
    -- Also apply combat-safe overlays (create/update overlays out of combat)
    if addon.ApplyPartyFrameHealthOverlays then
        addon.ApplyPartyFrameHealthOverlays()
    end
    if addon.ApplyPartyFrameNameOverlays then
        addon.ApplyPartyFrameNameOverlays()
    end
    -- Apply visibility settings (over absorb glow, heal prediction, absorb bars)
    if addon.ApplyPartyOverAbsorbGlowVisibility then
        addon.ApplyPartyOverAbsorbGlowVisibility()
    end
    if addon.ApplyPartyHealPredictionVisibility then
        addon.ApplyPartyHealPredictionVisibility()
    end
    if addon.ApplyPartyAbsorbBarsVisibility then
        addon.ApplyPartyAbsorbBarsVisibility()
    end
    if addon.ApplyPartyHealPredictionClipping then
        addon.ApplyPartyHealPredictionClipping()
    end
    -- Apply health bar borders
    if addon.ApplyPartyFrameHealthBarBorders then
        addon.ApplyPartyFrameHealthBarBorders()
    end
end

function Combat.queueRaidFrameReapply()
    addon.Events.RunOutOfCombat(applyRaidFrameStyles, "BarsCombat:raid")
end

function Combat.queuePartyFrameReapply()
    addon.Events.RunOutOfCombat(applyPartyFrameStyles, "BarsCombat:party")
end

return Combat
