--------------------------------------------------------------------------------
-- enforce.lua
-- Hide-Blizzard enforcement hooks (refactor #24)
-- One primitive for "hide a Blizzard region that Blizzard keeps re-showing":
-- apply the hide now, hook the region's Show/SetAlpha (and whatever else a site
-- names) once, and re-apply from the hook while a key says hidden. Before it,
-- about fifty installer functions in thirty files each carried their own copy
-- of the hook body, the install marker, and the re-entry guard.
--
-- Contract of the hook body (taint.md rules 1, 5, 9, 10, 11; secrets.md "How
-- Tables Become Secret"):
--   * it closes over the region and its FrameState table at install and never
--     reads its own arguments. A hook's `self` can arrive as a secret handle
--     from a sealed caller, and keying FrameState on one marks the table secret
--     for the session. The alpha argument is never compared: re-asserting 0
--     over a 0 is harmless behind the guard.
--   * every widget call is in pcall; state lives in FrameState, never on the
--     region.
--   * Hide, SetPoint, SetScale, ClearAllPoints are never hooked; SetShown is
--     refused on an Edit Mode system frame (a Lua override there). An apply
--     that needs Hide calls HideBase or Hide.
--   * a "defer" re-assert is a C_Timer.After(0) call-stack break, not a combat
--     latch; SetAlpha is legal in combat (rule 4).
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.Enforce = addon.Enforce or {}
local Enforce = addon.Enforce

local FS = addon.FrameState
local SS = addon.SecretSafe

local EMPTY = {}
local DEFAULT_TIMING = "sync"
local REFUSED = { Hide = true, SetPoint = true, SetScale = true, ClearAllPoints = true }

-- Every region with at least one key, for Dump. Weak keys: Blizzard regions
-- never collect, but the set must not be what keeps one alive.
local tracked = setmetatable({}, { __mode = "k" })

-- Resolved per call: core/editmode/core.lua loads after this file.
local function editModeOpen()
    local em = addon.EditMode
    local fn = em and em.IsEditModeActiveOrOpening
    if type(fn) ~= "function" then return false end
    return fn() == true
end

local function defaultApply(region)
    region:SetAlpha(0)
end

local function keyActive(entry)
    if entry.skipInEditMode and editModeOpen() then return false end
    if entry.when then
        return entry.when() == true
    end
    return entry.hidden == true
end

-- Run each active key's apply once, inside the shared guard.
-- method  the hooked method that fired in a sync run; nil for a direct call
--         and for a deferred run, which re-asserts every active key.
-- phase   "sync" or "defer".
local function runApplies(region, st, method, phase)
    if st.enforceApplying then return end
    st.enforceApplying = true
    for _, entry in pairs(st.enforce) do
        if (method == nil or entry.methods[method]) and keyActive(entry) then
            pcall(entry.apply, region, method, phase)
        end
    end
    st.enforceApplying = nil
end

local function fire(region, st, method)
    if st.enforceApplying then return end
    local timing = st.enforceTiming[method] or DEFAULT_TIMING
    if timing ~= "defer" then
        runApplies(region, st, method, "sync")
    end
    if timing ~= "sync" and not st.enforcePending then
        st.enforcePending = true
        C_Timer.After(0, st.enforceDeferred)
    end
end

local function screen(region)
    region = SS.plainFrame(region)
    if not region then return nil end
    if region.IsForbidden then
        local ok, forbidden = pcall(region.IsForbidden, region)
        if not ok or forbidden then return nil end
    end
    return region
end

-- Enforce.Install(region, key, opts)
-- Registers `key` on the region and hooks each named method once. Returns true
-- when the key is registered, false when the region fails the screen or no
-- method list is known for the key.
-- opts:
--   methods         required on first registration: the methods to hook. Each
--                   must be a function on the region.
--   apply           function(region, method, phase); the whole hide action, in
--                   pcall (default: region:SetAlpha(0)).
--   when            function() -> true, false, or nil; a live source of truth
--                   instead of the stored flag. nil skips (fail closed).
--   timing          "sync", "defer", "both", or { method = timing }. Two keys
--                   asking different timings for one method get "both".
--   skipInEditMode  hook bodies bail while Edit Mode is open or opening; a
--                   direct Set still applies.
--   restore         see Set.
function Enforce.Install(region, key, opts)
    region = screen(region)
    if not region or type(key) ~= "string" then return false end
    opts = opts or EMPTY
    local st = FS.Get(region)
    st.enforce = st.enforce or {}
    st.enforceHooked = st.enforceHooked or {}
    st.enforceTiming = st.enforceTiming or {}
    if not st.enforceDeferred then
        st.enforceDeferred = function()
            st.enforcePending = nil
            runApplies(region, st, nil, "defer")
        end
    end

    local entry = st.enforce[key]
    if not entry then
        entry = { hidden = false, methods = {}, apply = defaultApply }
        st.enforce[key] = entry
    end
    if opts.apply ~= nil then entry.apply = opts.apply end
    if opts.when ~= nil then entry.when = opts.when end
    if opts.restore ~= nil then entry.restore = opts.restore end
    if opts.skipInEditMode ~= nil then entry.skipInEditMode = opts.skipInEditMode end

    local methods = opts.methods
    if type(methods) ~= "table" then
        if next(entry.methods) == nil then return false end
        methods = EMPTY
    end
    local isSystemFrame = region.HideBase ~= nil
    local timing = opts.timing or DEFAULT_TIMING
    for _, m in ipairs(methods) do
        if not REFUSED[m] and not (m == "SetShown" and isSystemFrame)
            and type(region[m]) == "function" then
            entry.methods[m] = true
            local want = timing
            if type(timing) == "table" then want = timing[m] or DEFAULT_TIMING end
            local have = st.enforceTiming[m]
            if have and have ~= want then want = "both" end
            st.enforceTiming[m] = want
            if not st.enforceHooked[m] then
                local ok = pcall(hooksecurefunc, region, m, function()
                    fire(region, st, m)
                end)
                if ok then st.enforceHooked[m] = true end
            end
        end
    end
    tracked[region] = true
    return true
end

-- Run every active key's apply on the region now. For live-read sites after
-- a configuration change; a region with no key is left alone.
function Enforce.Apply(region)
    region = screen(region)
    if not region or not FS.Has(region) then return end
    local st = FS.Get(region)
    if st.enforce then
        runApplies(region, st, nil, "sync")
    end
end

-- Enforce.Set(region, key, hidden, opts)
-- The flag-driven entry point (Util.EnforceHidden). hidden true: Install, set
-- the flag, apply now; a key already hidden returns false without touching the
-- region, so a hot path pays a flag read. hidden false: clear the flag, run the
-- restore, then re-apply every other key still active on the region.
-- opts.restore  1 (SetAlpha(1)), another number, false (flag flip only), or
--               function(region). The Set(false) call's own value wins over
--               the one stored at Install; default 1.
function Enforce.Set(region, key, hidden, opts)
    opts = opts or EMPTY
    local plain = screen(region)
    if not plain then return false end
    local st = FS.Get(plain)
    local entry = st.enforce and st.enforce[key]
    if hidden then
        if entry and entry.hidden then return false end
        if not Enforce.Install(plain, key, opts) then return false end
        st.enforce[key].hidden = true
        runApplies(plain, st, nil, "sync")
        return true
    end

    local restore = opts.restore
    if restore == nil and entry then restore = entry.restore end
    if restore == nil then restore = 1 end
    if entry then entry.hidden = false end
    if type(restore) == "function" then
        pcall(restore, plain)
    elseif restore ~= false and plain.SetAlpha then
        pcall(plain.SetAlpha, plain, restore)
    end
    if st.enforce then
        runApplies(plain, st, nil, "sync")
    end
    return true
end

-- Stored flags only, no closure call, so a hot path can ask cheaply. With no
-- key: true when any key on the region is hidden. A live-read key ("when")
-- never reports hidden here.
function Enforce.IsHidden(region, key)
    local plain = SS.plainFrame(region)
    if not plain or not FS.Has(plain) then return false end
    local entries = FS.GetProp(plain, "enforce")
    if not entries then return false end
    if key ~= nil then
        local entry = entries[key]
        return entry ~= nil and entry.hidden == true
    end
    for _, entry in pairs(entries) do
        if entry.hidden == true then return true end
    end
    return false
end

-- Introspection: /scoot debug enforce, or /run ScootAddon.Enforce.Dump()
-- One line per region: its debug name, each key with hidden, live (a "when"
-- key), or off, and the hooked methods with their timing. Then the totals.
function Enforce.Dump()
    local rows = {}
    local regions, keys, hooks = 0, 0, 0
    for region in pairs(tracked) do
        local st = FS.Get(region)
        local name = "?"
        if region.GetDebugName then
            local ok, n = pcall(region.GetDebugName, region)
            if ok then name = SS.plainString(n) or "?" end
        end
        local keyParts = {}
        for key, entry in pairs(st.enforce or EMPTY) do
            local state = "off"
            if entry.when then
                state = "live"
            elseif entry.hidden then
                state = "hidden"
            end
            keyParts[#keyParts + 1] = key .. "=" .. state
            keys = keys + 1
        end
        table.sort(keyParts)
        local hookParts = {}
        for m in pairs(st.enforceHooked or EMPTY) do
            hookParts[#hookParts + 1] = m .. "(" .. (st.enforceTiming[m] or DEFAULT_TIMING) .. ")"
            hooks = hooks + 1
        end
        table.sort(hookParts)
        regions = regions + 1
        rows[#rows + 1] = ("%s: %s; hooks: %s"):format(
            name, table.concat(keyParts, " "), table.concat(hookParts, " "))
    end
    table.sort(rows)
    rows[#rows + 1] = ("regions: %d, keys: %d, hooks: %d"):format(regions, keys, hooks)
    if addon.DebugShowWindow then
        addon.DebugShowWindow(("Enforce (%d regions)"):format(regions), rows)
    end
    return rows
end

addon:RegisterDebugCommand({
    name = "enforce",
    help = "Hide-enforcement hooks: every region, its keys, and the hooked methods",
    handler = function() Enforce.Dump() end,
})
