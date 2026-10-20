--------------------------------------------------------------------------------
-- core/specs.lua
-- The class and specialization catalog: every class's specs in Blizzard's
-- order, the player's current spec, and the walks between a spec and its
-- class. One enumeration for the Rules page, the aura tracker's spec gate and
-- its spec fly-out; before this each kept a copy of the walk.
--
-- Buckets caches only once the build is non-empty: an empty build captured
-- before login would stick for the session and strand every caller.
-- HasSpecAxis is the question a client with no specializations answers
-- false; a caller that reads false before the world pass asks again.
--------------------------------------------------------------------------------
local addonName, addon = ...

addon.Specs = addon.Specs or {}
local Specs = addon.Specs

local SPEC_CACHE = nil
local SPEC_BY_ID = nil
local MAX_CLASS_ID_GAP = 8

-- The spec getters moved under C_SpecializationInfo in 12.x. The bare
-- globals are Blizzard's deprecation aliases, loaded only on the standard and
-- classic game types with loadDeprecationFallbacks on, so Forever never has
-- them; the namespaced call is tried first.
local function specAPI(name)
    local fn = C_SpecializationInfo and C_SpecializationInfo[name] or _G[name]
    return type(fn) == "function" and fn or nil
end

--- Every class with its specs, sorted by class name, and the same spec entries
-- keyed by id:
--   { { classID, name, file, specs = { { classID, className, file, specID, name, icon } } } },
--   { [specID] = specEntry }
function Specs.Buckets()
    if SPEC_CACHE then
        return SPEC_CACHE, SPEC_BY_ID
    end
    SPEC_BY_ID = {}
    SPEC_CACHE = {}

    local numForClass = specAPI("GetNumSpecializationsForClassID")
    local infoForClass = specAPI("GetSpecializationInfoForClassID")
    if type(GetNumClasses) ~= "function" or type(GetClassInfo) ~= "function" then
        return SPEC_CACHE, SPEC_BY_ID
    end

    -- GetClassInfo takes a class ID, and the IDs have gaps where a ruleset
    -- lacks a class: vanilla's nine skip 6 (Death Knight) and end at 11
    -- (Druid), and on Forever GetNumClasses answers 9, so a walk to 9 found
    -- eight and dropped the Druid. The walk runs until it has
    -- found that many classes, with a cap in case the count and the IDs
    -- disagree.
    local totalClasses = GetNumClasses() or 0
    local found = 0
    local classIndex = 0
    while found < totalClasses and classIndex < totalClasses + MAX_CLASS_ID_GAP do
        classIndex = classIndex + 1
        local className, classFile, classID = GetClassInfo(classIndex)
        if classID then
            found = found + 1
            local classEntry = {
                classID = classID,
                name = className or ("Class " .. tostring(classIndex)),
                file = classFile,
                specs = {},
            }

            local count = numForClass and infoForClass and numForClass(classID) or 0
            for specIndex = 1, count do
                local specID, specName, _, specIcon = infoForClass(classID, specIndex)
                if specID then
                    local specEntry = {
                        classID = classID,
                        className = classEntry.name,
                        file = classFile,
                        specID = specID,
                        name = specName or ("Spec " .. tostring(specIndex)),
                        icon = specIcon,
                    }
                    table.insert(classEntry.specs, specEntry)
                    SPEC_BY_ID[specID] = specEntry
                end
            end

            table.insert(SPEC_CACHE, classEntry)
        end
    end

    table.sort(SPEC_CACHE, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)

    -- Cache only once the class data is really there: an empty build captured
    -- before login would stick for the session and strand every caller.
    if #SPEC_CACHE == 0 then
        local empty, emptyById = SPEC_CACHE, SPEC_BY_ID
        SPEC_CACHE, SPEC_BY_ID = nil, nil
        return empty, emptyById
    end

    return SPEC_CACHE, SPEC_BY_ID
end

--- The class token a spec belongs to ("PRIEST" for 258), or nil.
function Specs.ClassTokenForSpec(specID)
    if type(specID) ~= "number" then return nil end
    local _, byId = Specs.Buckets()
    local entry = byId and byId[specID]
    return entry and entry.file or nil
end

--- Spec ids for a class token ("PRIEST"), in Blizzard's order; empty when the
-- token is unknown or the class data has not loaded.
function Specs.SpecIDsForClass(token)
    local out = {}
    if type(token) ~= "string" then return out end
    local buckets = Specs.Buckets()
    for _, classEntry in ipairs(buckets) do
        if classEntry.file == token then
            for _, spec in ipairs(classEntry.specs) do
                if type(spec.specID) == "number" then out[#out + 1] = spec.specID end
            end
            break
        end
    end
    return out
end

--- The player's current spec id, nil before the talent data loads.
function Specs.CurrentSpecID()
    local getSpec, getInfo = specAPI("GetSpecialization"), specAPI("GetSpecializationInfo")
    if not getSpec or not getInfo then return nil end
    local ok, specIndex = pcall(getSpec)
    if not ok or type(specIndex) ~= "number" then return nil end
    local infoOk, specID = pcall(getInfo, specIndex)
    if infoOk and type(specID) == "number" and specID > 0 then return specID end
    return nil
end

--- Whether this client has specializations at all: true when any class
-- reports one. False before the class data loads as well, so a caller that
-- reads false before the world pass asks again.
function Specs.HasSpecAxis()
    local buckets = Specs.Buckets()
    for _, classEntry in ipairs(buckets) do
        if #classEntry.specs > 0 then return true end
    end
    return false
end
