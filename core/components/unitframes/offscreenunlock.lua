-- offscreenunlock.lua - Off-screen drag for the Player and Target frames:
-- a descriptor over addon.OffscreenUnlock.NewFamily. The clamp removal,
-- enforcement hooks, Edit Mode nudge, and combat deferral live in
-- core/editmode/offscreenunlock.lua. The nudge lands on the Edit Mode
-- registered frame only; the global PlayerFrame/TargetFrame get the clamp
-- work too.
local addonName, addon = ...

local function readAllowOffscreen(unit)
    -- Zero-touch friendly: avoid creating tables here (use rawget only).
    local profile = addon and addon.db and addon.db.profile
    local uf = profile and rawget(profile, "unitFrames")
    local unitCfg = (type(uf) == "table") and rawget(uf, unit) or nil
    local misc = (type(unitCfg) == "table") and rawget(unitCfg, "misc") or nil
    if type(misc) ~= "table" then
        return false
    end
    return rawget(misc, "allowOffscreenDrag") == true
end

local Family = addon.OffscreenUnlock.NewFamily({
    keys = { "Player", "Target" },
    isEnabled = function(unit) return addon:IsModuleEnabled("unitFrames", unit) end,
    resolveFrame = addon.GetEditModeUnitFrame,
    extraFrames = function(unit)
        if unit == "Player" then return { _G.PlayerFrame } end
        if unit == "Target" then return { _G.TargetFrame } end
    end,
    readSetting = readAllowOffscreen,
    combatKey = function(unit) return "UnitFrames:OffscreenUnlock:" .. unit end,
    debugFlag = "_dbgOffscreenUnlock",
    debugTag = "[OffscreenUnlock]",
})

addon.ApplyUnitFrameOffscreenUnlockFor = Family.applyFor
addon.ApplyAllUnitFrameOffscreenUnlocks = Family.applyAll
addon.OnUnitFrameOffscreenUnlockLayoutsUpdated = Family.onLayoutsUpdated

Family.installEditModeHooks()
