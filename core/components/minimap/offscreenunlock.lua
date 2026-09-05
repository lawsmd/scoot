-- offscreenunlock.lua - Off-screen drag for the Minimap cluster: a descriptor
-- over addon.OffscreenUnlock.NewFamily. The clamp removal, enforcement hooks,
-- Edit Mode nudge, and combat deferral live in core/editmode/offscreenunlock.lua.
local addonName, addon = ...

-- Prefer the Edit Mode registered system frame, which is what Edit Mode drags.
local function resolveMinimapFrame()
    local mgr = _G.EditModeManagerFrame
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if mgr and EMSys and mgr.GetRegisteredSystemFrame then
        local frame = mgr:GetRegisteredSystemFrame(EMSys.Minimap)
        if frame then return frame end
    end
    return _G.MinimapCluster
end

local function readAllowOffscreen()
    -- Zero-touch friendly: avoid creating tables here (use rawget only).
    local profile = addon and addon.db and addon.db.profile
    local components = profile and rawget(profile, "components")
    local minimapStyle = (type(components) == "table") and rawget(components, "minimapStyle") or nil
    if type(minimapStyle) ~= "table" then
        return false
    end
    return rawget(minimapStyle, "allowOffScreenDragging") == true
end

local Family = addon.OffscreenUnlock.NewFamily({
    keys = { "Minimap" },
    resolveFrame = resolveMinimapFrame,
    readSetting = readAllowOffscreen,
    combatKey = function() return "Minimap:OffscreenUnlock" end,
    debugFlag = "_dbgMinimapOffscreenUnlock",
    debugTag = "[MinimapOffscreenUnlock]",
    propPrefix = "minimap",
})

addon.ApplyMinimapOffscreenUnlock = function() return Family.applyFor("Minimap") end

Family.installEditModeHooks()
