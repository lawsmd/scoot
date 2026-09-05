--------------------------------------------------------------------------------
-- refresh.lua
-- Ordered apply chains (refactor #34)
-- One catalog of the restyle sequences that live outside the component loop:
-- the unit-frame and group-frame tails of addon:ApplyStyles, the per-unit
-- chains the reactive handlers run after Blizzard rebuilds a frame, the
-- group-frame combat drains, the category reset, and unit-to-unit copy.
-- A chain holds function NAMES resolved as addon[name] on every call:
-- cast/boss.lua, unitframes/auracontainer.lua, and text/names.lua re-wrap an
-- applier after it is first defined, so a captured function value would call
-- the pre-wrap version. Gates (module toggles, combat, Zero-Touch) stay at
-- the call sites; a chain is order and nothing else.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.Refresh = addon.Refresh or {}
local Refresh = addon.Refresh

local Chains = {
    -- addon:ApplyStyles, unit frames block. Gate: IsModuleEnabled("unitFrames").
    -- Text before bars before portraits; opacity after everything that creates
    -- a region; scale and the ToT/FocusTarget geometry last.
    unitFrames = {
        "ApplyAllUnitFrameHealthTextVisibility",
        "ApplyAllUnitFramePowerTextVisibility",
        "ApplyAllUnitFrameNameLevelText",
        "ApplyAllUnitFrameBarTextures",
        "ApplyAllUnitFramePortraits",
        "ApplyAllUnitFrameClassResources",
        "ApplyAllUnitFrameCastBars",
        "ApplyAllUnitFrameBuffsDebuffs",
        "ApplyAllUnitFrameVisibility",
        "ApplyAllThreatMeterVisibility",
        "ApplyTargetBossIconVisibility",
        "ApplyBossHighLevelIconVisibility",
        "ApplyAllPlayerMiscVisibility",
        "ApplyPetFrameVisibility",
        "ApplyAllUnitFrameOffscreenUnlocks",
        "ApplyAllUnitFrameScaleMults",
        "ApplyAllToTSettings",
        "ApplyAllFocusTargetSettings",
    },

    -- Group frames. Keys are the settings frameKey, so GF.applyStyles(frameKey)
    -- is Refresh.Run(frameKey). ApplyStyles gates each on
    -- IsModuleEnabled("groupFrames", key); the combat drains run them ungated.
    -- Order: bar fill first (the health overlay's texture fallback copies the
    -- live fill), name overlays and container visibility before the roster
    -- overlay (it reads both). Every other position is free; the borders
    -- defer their work one frame regardless of where they sit.
    raid = {
        "ApplyRaidFrameHealthBarStyle",
        "ApplyRaidFrameStatusTextStyle",
        "ApplyRaidFrameGroupTitlesStyle",
        "ApplyRaidFrameHealthOverlays",
        "ApplyRaidFrameNameOverlays",
        "ApplyRaidFrameHealthBarBorders",
        "ApplyRaidOverAbsorbGlowVisibility",
        "ApplyRaidHealPredictionVisibility",
        "ApplyRaidAbsorbBarsVisibility",
        "ApplyRaidHealPredictionClipping",
        "ApplyRaidGroupLeadIcons",
        "ApplyRaidContainerVisibility",
        "ApplyRaidRosterOverlay",
    },
    party = {
        "ApplyPartyFrameHealthBarStyle",
        "ApplyPartyFrameTitleStyle",
        "ApplyPartyFrameStatusTextStyle",
        "ApplyPartyFrameHealthOverlays",
        "ApplyPartyFrameNameOverlays",
        "ApplyPartyFrameHealthBarBorders",
        "ApplyPartyOverAbsorbGlowVisibility",
        "ApplyPartyHealPredictionVisibility",
        "ApplyPartyAbsorbBarsVisibility",
        "ApplyPartyHealPredictionClipping",
        "ApplyPartyGroupLeadIcons",
    },
    -- Text-only settings edits (GF.applyText). Each is a strict subsequence
    -- of its family chain above, so relative order is the family order.
    raidText = {
        "ApplyRaidFrameStatusTextStyle",
        "ApplyRaidFrameGroupTitlesStyle",
        "ApplyRaidFrameNameOverlays",
    },
    partyText = {
        "ApplyPartyFrameTitleStyle",
        "ApplyPartyFrameStatusTextStyle",
        "ApplyPartyFrameNameOverlays",
    },

    -- Per unit: every name is called as fn(unit).
    -- Full restyle of one unit (settings copy, category reset). The cast bar
    -- applier returns early for every unit but Player, Target, and Focus.
    unit = {
        "ApplyUnitFrameScaleMultFor",
        "ApplyUnitFrameBarTexturesFor",
        "ApplyUnitFrameHealthTextVisibilityFor",
        "ApplyUnitFramePowerTextVisibilityFor",
        "ApplyUnitFrameNameLevelTextFor",
        "ApplyUnitFramePortraitFor",
        "ApplyUnitFrameCastBarFor",
        "ApplyUnitFrameBuffsDebuffsFor",
        "ApplyUnitFrameVisibilityFor",
    },
    -- After TargetFrame_Update or FocusFrame_Update: the light chain. The
    -- text appliers no-op until a full ApplyStyles pass has filled their font
    -- cache, which ClearFrameLevelState wipes on a profile switch.
    unitSwap = {
        "ApplyUnitFrameBarTexturesFor",
        "ApplyUnitFrameNameLevelTextFor",
        "ApplyUnitFrameHealthTextVisibilityFor",
        "ApplyUnitFramePowerTextVisibilityFor",
    },
    -- After Boss frames appear or update. The last two take no unit.
    unitBoss = {
        "ApplyUnitFrameBarTexturesFor",
        "ApplyUnitFrameHealthTextVisibilityFor",
        "ApplyUnitFramePowerTextVisibilityFor",
        "ApplyBossCastBarFor",
        "ApplyBossHighLevelIconVisibility",
    },
}
for _, list in pairs(Chains) do
    table.freeze(list)
end
table.freeze(Chains)
Refresh.Chains = Chains

-- Runs a chain in order, passing every argument to each function. A name with
-- nothing behind it is skipped, as the guarded call sites this replaced did;
-- Dump reports it.
function Refresh.Run(chain, ...)
    local list = Chains[chain]
    if not list then
        error("Refresh.Run: unknown chain " .. tostring(chain), 2)
    end
    for i = 1, #list do
        local fn = addon[list[i]]
        if fn then
            fn(...)
        end
    end
end

-- Introspection for verification: /run ScootAddon.Refresh.Dump()
-- One line per chain, names in order, unresolved names marked (MISSING).
function Refresh.Dump()
    local names, lines, missing = {}, {}, 0
    for chain in pairs(Chains) do
        names[#names + 1] = chain
    end
    table.sort(names)
    for _, chain in ipairs(names) do
        local parts = {}
        for i, name in ipairs(Chains[chain]) do
            if type(addon[name]) == "function" then
                parts[i] = name
            else
                parts[i] = name .. " (MISSING)"
                missing = missing + 1
            end
        end
        lines[#lines + 1] = ("%s (%d): %s"):format(chain, #parts, table.concat(parts, ", "))
    end
    lines[#lines + 1] = ("missing: %d"):format(missing)
    if addon.DebugShowWindow then
        addon.DebugShowWindow(("Refresh (%d chains, %d missing)"):format(#names, missing), lines)
    end
    return lines
end
