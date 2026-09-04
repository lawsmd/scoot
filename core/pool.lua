--------------------------------------------------------------------------------
-- pool.lua
-- Shared object pools (refactor #29)
-- Two shapes, one per dialect the hand-rolled pools used:
--   Pool.New(createFn, resetFn)        a free list. Acquire pops or creates,
--                                      Release resets and pushes.
--   Pool.NewIndexed(createFn, hideFn)  a lazily grown array where the index is
--                                      the object's identity. Get(i) creates on
--                                      first use, HideFrom(n) hides the tail.
-- A pool owns its list and nothing else. Hiding, re-parenting, and clearing
-- text or anchors stay in the caller's create, reset, and hide functions:
-- every site has its own idea of a clean object, and some (the CDM overlays,
-- the vertical stacks) have parts that must never be touched. Active-object
-- tracking stays with the caller too. Each site keys its live objects
-- differently (by CDM icon, by owner, by insertion order) and other files
-- read those tables.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.Pool = addon.Pool or {}
local Pool = addon.Pool

--------------------------------------------------------------------------------
-- Stack pool
--------------------------------------------------------------------------------

local StackPool = {}
StackPool.__index = StackPool

--- createFn(...) receives Acquire's arguments and returns the new object, or
--- nil to refuse (the anim engine refuses in combat). resetFn(obj) runs on
--- Release before the push and is optional.
function Pool.New(createFn, resetFn)
    return setmetatable({ free = {}, create = createFn, reset = resetFn }, StackPool)
end

--- Returns the object and whether this call created it.
function StackPool:Acquire(...)
    local obj = table.remove(self.free)
    if obj ~= nil then
        return obj, false
    end
    obj = self.create(...)
    if obj == nil then
        return nil
    end
    return obj, true
end

function StackPool:Release(obj)
    if obj == nil then return end
    if self.reset then
        self.reset(obj)
    end
    self.free[#self.free + 1] = obj
end

--- Creates n objects up front. createFn returns them hidden; resetFn does not
--- run. Stops at the first nil so a refusing createFn refuses here too.
function StackPool:Preallocate(n)
    for _ = 1, n do
        local obj = self.create()
        if obj == nil then return end
        self.free[#self.free + 1] = obj
    end
end

function StackPool:FreeCount()
    return #self.free
end

--------------------------------------------------------------------------------
-- Indexed pool
--------------------------------------------------------------------------------

local IndexedPool = {}
IndexedPool.__index = IndexedPool

--- createFn(i, ...) receives the index and Get's extra arguments. hideFn(obj)
--- is what HideFrom calls per object; the default is obj:Hide().
function Pool.NewIndexed(createFn, hideFn)
    return setmetatable({ items = {}, create = createFn, hide = hideFn }, IndexedPool)
end

function IndexedPool:Get(i, ...)
    local obj = self.items[i]
    if obj == nil then
        obj = self.create(i, ...)
        self.items[i] = obj
    end
    return obj
end

--- Hides items[n] through the end of the array. Index 0 is a legal start (the
--- damage meter divider strips number their boundaries from 0).
function IndexedPool:HideFrom(n)
    local items, hide = self.items, self.hide
    for i = n, #items do
        local obj = items[i]
        if obj ~= nil then
            if hide then hide(obj) else obj:Hide() end
        end
    end
end

function IndexedPool:Count()
    return #self.items
end
