--------------------------------------------------------------------------------
-- frames.lua
-- Shared unit-frame and Edit Mode frame resolution (refactor #22)
-- Input vocabulary: PascalCase unit keys ("Player", "Target", "Focus", "Pet",
-- "Boss", "TargetOfTarget", "FocusTarget"; the strict path also accepts
-- "Party" and "Raid"). Callers with other vocabularies (lowercase debug keys,
-- ui/v2 componentIds) translate at their own edge.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.Frames = addon.Frames or {}
local Frames = addon.Frames

Frames.NUM_BOSS_FRAMES = 5
addon.NUM_BOSS_FRAMES = Frames.NUM_BOSS_FRAMES

-- Order is load-bearing: bars.lua serializes baseline snapshots in this order.
Frames.UNITS = { "Player", "Target", "Focus", "Boss", "Pet", "TargetOfTarget", "FocusTarget" }
Frames.CORE_UNITS = { "Player", "Target", "Focus", "Pet" }
Frames.UNIT_KEY_BY_COMPONENT = {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus = "Focus",
    ufPet = "Pet",
    ufToT = "TargetOfTarget",
    ufBoss = "Boss",
    ufFocusTarget = "FocusTarget",
}

local EM_INDEX_KEY = {
    Player = "Player",
    Target = "Target",
    Focus = "Focus",
    Pet = "Pet",
    Boss = "Boss",
    Party = "Party",
    Raid = "Raid",
}

local GLOBAL_FALLBACK = {
    Player = "PlayerFrame",
    Target = "TargetFrame",
    Focus = "FocusFrame",
    Pet = "PetFrame",
    Boss = "Boss1TargetFrame",
}

-- Strict: the Edit Mode registered system frame or nil, never a _G fallback.
-- Use whenever the result feeds EditMode.GetSetting/WriteSetting or position
-- sync; a raw global there could write settings to the wrong object.
function addon.GetEditModeUnitFrame(unit)
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
    local key = EM_INDEX_KEY[unit]
    local idx = key and EM[key]
    if not idx then return nil end
    return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
end

-- Styling: best-effort live frame. ToT/FocusTarget are not Edit Mode systems;
-- every other unit prefers the registry, then the _G frame (the registry
-- returns the same objects on retail, so the fallback can only supply a frame
-- where the registry gave nil, never a different frame).
function addon.GetUnitFrame(unit)
    if unit == "TargetOfTarget" then return _G.TargetFrameToT end
    if unit == "FocusTarget" then return _G.FocusFrameToT end
    local f = addon.GetEditModeUnitFrame(unit)
    if f then return f end
    local name = GLOBAL_FALLBACK[unit]
    if name then return _G[name] end
end

-- Accepts a number or a numeric string (several sites parse the index out of
-- a baseline key like "Boss3"); concat coerces both.
function addon.GetBossFrame(i)
    if not i then return nil end
    return _G["Boss" .. i .. "TargetFrame"]
end

-- fn(bossFrame, i); nil frames are skipped, matching the "if bossFrame then"
-- guard every hand-rolled loop carried.
function addon.ForEachBossFrame(fn)
    for i = 1, Frames.NUM_BOSS_FRAMES do
        local f = _G["Boss" .. i .. "TargetFrame"]
        if f then fn(f, i) end
    end
end
