--------------------------------------------------------------------------------
-- forever/dynamiclayouts.lua
-- The host side of Dynamic Layouts on Camelot: where the dynamic records and
-- the per-profile trigger set and speed live in CamelotDB, and the profile
-- pass that feeds the resolver's mask. The engine (core/dynamiclayouts/)
-- reads addon.DynamicLayoutsStore at call time and never touches the
-- database itself, so the other addon sets a store of its own.
--
-- A frame's record sits beside its Edit Mode positions:
--   layout[key] = { positions = { [layoutName] = { point, x, y } },
--                   dynamic = { enabled, point, x, y, scale, opacity } }
-- A profile is one Edit Mode layout, so the record needs no layout key. x and
-- y are in the frame's own scale, what SetPoint takes; an editor writing them
-- at the dynamic scale stores what GetPoint reports there. A missing field
-- leaves that channel at base.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB
local DL = addon.DynamicLayouts
local Resolver = DL.Resolver

local TRIGGERS = { "inCombat", "targetAcquired", "insideInstance" }
local SPEED_PATH = "dynamicLayouts.speed"

local function triggerPath(name)
    return "dynamicLayouts.trigger." .. name
end

DB.RegisterDefaults({
    [triggerPath("inCombat")] = true,
    [triggerPath("targetAcquired")] = true,
    [triggerPath("insideInstance")] = true,
    [SPEED_PATH] = DL.SPEED_DEFAULT,
})

addon.DynamicLayoutsStore = {
    GetRecord = function(id)
        local entry = DB.GetLayout(id)
        return entry and entry.dynamic or nil
    end,
    --- Merge fields into the record, creating it. A nil in `fields` cannot
    --- clear a field; pass false for enabled.
    SetRecord = function(id, fields)
        if type(id) ~= "string" or type(fields) ~= "table" then return false end
        local entry = DB.GetLayout(id) or {}
        entry.dynamic = entry.dynamic or {}
        for k, v in pairs(fields) do
            entry.dynamic[k] = v
        end
        return DB.SetLayout(id, entry)
    end,
    GetTrigger = function(name)
        return DB.Get(triggerPath(name)) and true or false
    end,
    SetTrigger = function(name, on)
        return DB.Set(triggerPath(name), on and true or false)
    end,
    GetSpeed = function()
        return DB.Get(SPEED_PATH)
    end,
    SetSpeed = function(seconds)
        return DB.Set(SPEED_PATH, seconds)
    end,
}

local function mask()
    local out = {}
    for _, name in ipairs(TRIGGERS) do
        out[name] = addon.DynamicLayoutsStore.GetTrigger(name)
    end
    return out
end

-- Last, after every step that re-lands a base: the unit frames (10), the
-- cast bar and the objective tracker (20), the components (30). A profile
-- switch then lands the dynamic state on top of whatever those wrote. The
-- initial pass feeds the mask and nothing else: no frame exists yet, and the
-- resolver's first resolution lands after the world entry. A resync pass
-- keeps the profile it had, so a snap there would only cut short the tween
-- that leaving Edit Mode starts; the two component steps skip it too.
addon.Profiles.RegisterApplyStep("camelotDynamicLayouts", function(_, ctx)
    Resolver.SetEnabledMask(mask())
    if ctx.initial or ctx.resync then return end
    DL.RefreshAll("snap")
end, 40)
