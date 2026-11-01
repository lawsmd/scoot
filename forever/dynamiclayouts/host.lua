--------------------------------------------------------------------------------
-- forever/dynamiclayouts/host.lua
-- The host side of Dynamic Layouts on Camelot: the Features row, where the
-- dynamic records, the per-profile trigger set, the two transition speeds
-- (into the dynamic layout, out of it), the delay before the return to it
-- and the target rule live in CamelotDB, and the profile pass that feeds the
-- resolver's mask. The engine
-- (core/dynamiclayouts/) reads addon.DynamicLayoutsStore at call time and
-- never touches the database itself, so the other addon sets a store of its
-- own.
--
-- A frame's record sits beside its Edit Mode positions:
--   layout[key] = { positions = { [layoutName] = { point, x, y } },
--                   dynamic = { point, x, y, scale, opacity, offscreen } }
-- Whether a frame takes part is not in its record: it is one setting per
-- participation key, dynamicLayouts.participating.<key>, the key being the
-- frame's group (registered below) or its own id. One checkbox in the view
-- stands for every frame under a key.
-- A profile is one Edit Mode layout, so the record needs no layout key. x and
-- y are in the frame's own scale, what SetPoint takes; an editor writing them
-- at the dynamic scale stores what GetPoint reports there. A missing field
-- leaves that channel at base; offscreen names the screen edge the frame
-- leaves by, or is absent.
--
-- The feature switch is read once per session, as every Features row is.
-- Off, the store answers no record, so every adapter stays at base and the
-- Edit Mode strip never builds.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB
local DL = addon.DynamicLayouts
local Resolver = DL.Resolver

local FEATURE_PATH = "dynamicLayouts.enabled"
local TRIGGERS = { "inCombat", "targetAcquired", "insideInstance" }
-- One duration per direction; forever/db.lua's migration 3 seeds both from
-- the one speed that preceded them.
local SPEED_PATHS = { ["in"] = "dynamicLayouts.speedIn", out = "dynamicLayouts.speedOut" }
-- Seconds the return to the dynamic layout waits after the last requirement
-- is met; a file from before it reads the default, 0.
local DELAY_PATH = "dynamicLayouts.delay"
-- The target requirement counts only an NPC the player can attack while
-- this is on; a file from before it reads the default, on.
local TARGET_RULE_PATH = "dynamicLayouts.targetAttackableNPCs"

local function triggerPath(name)
    return "dynamicLayouts.trigger." .. name
end

local function participatingPath(key)
    return "dynamicLayouts.participating." .. key
end

-- The view's checkboxes for frames that come in families, in list order.
-- forever/db.lua's migration 2 maps the old per-frame records onto these keys.
DL.RegisterGroup("unitFrames", "Unit Frames", 10)
DL.RegisterGroup("castBars", "Cast Bars", 20)
DL.RegisterGroup("actionBarClusters", "Action Bar Clusters", 30)
DL.RegisterGroup("microBags", "Micro & Bag Bar", 40)
DL.RegisterGroup("stanceBar", "Stance Bar", 45)
DL.RegisterGroup("gamepadBar", "Gamepad Bars", 46)
DL.RegisterGroup("objectiveTracker", "Objective Tracker", 50)
DL.RegisterGroup("statusBars", "Status Bars", 60)

DB.RegisterDefaults({
    [FEATURE_PATH] = true,
    [triggerPath("inCombat")] = true,
    [triggerPath("targetAcquired")] = true,
    [triggerPath("insideInstance")] = true,
    -- The owner's timings off the beta's saved profile: the move into the
    -- dynamic state over 1 second, out of it over the engine's 0.5, and the
    -- return to it 10 seconds after the last trigger ends. The engine's own
    -- are 0.5 and 0, which a preset start keeps.
    [SPEED_PATHS["in"]] = 1,
    [SPEED_PATHS.out] = DL.SPEED_DEFAULT,
    [DELAY_PATH] = 10,
    [TARGET_RULE_PATH] = DL.TARGET_ATTACKABLE_NPCS_DEFAULT,
})
DB.RegisterStock({
    [SPEED_PATHS["in"]] = DL.SPEED_DEFAULT,
    [DELAY_PATH] = DL.DELAY_DEFAULT,
})

-- Listed after components.lua in the TOC, so the row follows Minimap and
-- Tooltip under Interface.
addon.Features.Register({ group = "interface", groupLabel = "Interface",
    id = "dynamicLayouts", label = "Dynamic Layouts", path = FEATURE_PATH })

local function enabled()
    return DB.SessionGet(FEATURE_PATH) == true
end

-- Camelot's own records, by frame id: what a profile started as Camelot reads
-- while it stores no record of its own. A preset start has none. The first
-- write stores a copy and merges into it, so a stored record always wins.
local defaultRecords = {}

local function defaultRecord(id)
    local rec = defaultRecords[id]
    if not rec or DB.StartingPoint() ~= "camelot" then return nil end
    local copy = {}
    for k, v in pairs(rec) do copy[k] = v end
    return copy
end

addon.DynamicLayoutsStore = {
    IsEnabled = enabled,
    GetRecord = function(id)
        if not enabled() then return nil end
        local entry = DB.GetLayout(id)
        if entry and entry.dynamic then return entry.dynamic end
        return defaultRecord(id)
    end,
    --- Register Camelot's record for one frame id, in the stored shape
    --- (the header). Called at load, beside the frame's other defaults.
    RegisterDefaultRecord = function(id, record)
        if type(id) ~= "string" or type(record) ~= "table" then return false end
        defaultRecords[id] = record
        return true
    end,
    GetParticipating = function(key)
        if not enabled() or type(key) ~= "string" then return false end
        return DB.Get(participatingPath(key)) == true
    end,
    -- False, not nil, for off: a key Camelot enrolls by default would read
    -- its default back through a nil.
    SetParticipating = function(key, on)
        if type(key) ~= "string" then return false end
        return DB.Set(participatingPath(key), on and true or false)
    end,
    --- Merge fields into the record, creating it from Camelot's own when the
    --- profile has none. A nil in `fields` cannot clear a field; pass false
    --- to clear one.
    SetRecord = function(id, fields)
        if type(id) ~= "string" or type(fields) ~= "table" then return false end
        local entry = DB.GetLayout(id) or {}
        entry.dynamic = entry.dynamic or defaultRecord(id) or {}
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
    --- direction: "in", the transition into the dynamic layout, or "out".
    GetSpeed = function(direction)
        local path = SPEED_PATHS[direction]
        return path and DB.Get(path) or nil
    end,
    SetSpeed = function(direction, seconds)
        local path = SPEED_PATHS[direction]
        if not path then return false end
        return DB.Set(path, seconds)
    end,
    GetDelay = function()
        return DB.Get(DELAY_PATH)
    end,
    SetDelay = function(seconds)
        return DB.Set(DELAY_PATH, seconds)
    end,
    GetTargetAttackableNPCs = function()
        return DB.Get(TARGET_RULE_PATH) and true or false
    end,
    SetTargetAttackableNPCs = function(on)
        return DB.Set(TARGET_RULE_PATH, on and true or false)
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
