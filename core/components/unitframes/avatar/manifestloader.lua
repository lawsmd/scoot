-- manifestloader.lua - validates the generated manifest and builds fast lookup
-- indexes. The compositor and editor read the avatar data only through this layer.
local addonName, addon = ...

addon.Avatar = addon.Avatar or {}
local A = addon.Avatar

local cache -- { manifest, raceVariant[race][slot][key] = variantMeta }

local function build()
    local man = addon.AvatarManifest
    if type(man) ~= "table" or type(man.races) ~= "table" then
        return nil
    end
    local raceVariant = {}
    for race, rdata in pairs(man.races) do
        local slots = {}
        if type(rdata.variants) == "table" then
            for slot, list in pairs(rdata.variants) do
                local byKey = {}
                for _, v in ipairs(list) do
                    byKey[v.key] = v
                end
                slots[slot] = byKey
            end
        end
        raceVariant[race] = slots
    end
    return { manifest = man, raceVariant = raceVariant }
end

local function ensure()
    if not cache then
        cache = build()
    end
    return cache
end

function A.GetManifest()
    local c = ensure()
    return c and c.manifest or nil
end

function A.HasRace(race)
    if type(race) ~= "string" then return false end
    local man = A.GetManifest()
    return (man and man.races and man.races[race]) ~= nil
end

function A.GetRaceData(race)
    local man = A.GetManifest()
    return man and man.races and man.races[race] or nil
end

function A.GetVariant(race, slot, key)
    local c = ensure()
    if not c then return nil end
    local r = c.raceVariant[race]
    local s = r and r[slot]
    return s and s[key] or nil
end

function A.GetSlotLayer(slot)
    local man = A.GetManifest()
    return man and man.slotLayer and man.slotLayer[slot] or nil
end

-- Build a sprite path: <prefix><res>\<race>\<slot>_<key>.png
function A.BuildPath(res, race, slot, key)
    local man = A.GetManifest()
    if not man or not man.pathPrefix then return nil end
    return man.pathPrefix .. tostring(res) .. "\\" .. race .. "\\" .. slot .. "_" .. key .. ".png"
end

-- Light validation: confirm every default variant key exists. Logs through the
-- addon debug channel if available; never errors.
function A.ValidateManifest()
    local man = A.GetManifest()
    if not man then return false, "no manifest" end
    local problems = 0
    for race, rdata in pairs(man.races or {}) do
        for _, defaults in pairs(rdata.defaultsBySex or {}) do
            for slot, key in pairs(defaults) do
                if key ~= "none" and not A.GetVariant(race, slot, key) then
                    problems = problems + 1
                    if addon.DebugPrint then
                        addon.DebugPrint("avatar", "missing variant", race, slot, key)
                    end
                end
            end
        end
    end
    return problems == 0, problems
end
