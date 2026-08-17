-- scootauras/cadence.lua - "Lock drain to original duration" for bar trackers
--
-- The engine binds elem.barFill through SetDurationBar and drives its fill as
-- remaining / current duration; when a mechanic extends the aura, Blizzard
-- reports the extended value as the new total, so the bar refills and its
-- drain speed changes. This module keeps a second, invisible StatusBar (the
-- "lock bar", entry.lockBar, outside every button tree) at
-- remaining / originalDuration, and regions.lua composes the two
-- geometrically (deplete: barFill clipped to the lock bar's fill; fill: a
-- lock-clipped overlay unioned with barFill). No Lua ever reads or compares
-- a duration: both numbers travel as secrets into StatusBar sinks
-- (SetMinMaxValues / SetValue are AllowedWhenTainted).
--
-- Source of the numbers: StatusBar:GetTimerDuration() on the Scoot-bound
-- barFill returns the button's private LuaDurationObject by reference
-- (the object's HasSecretValues flips from false to
-- true across a pull). Configure asks once, under the structural gate, and
-- keeps the reference; Blizzard mutates the object in place, so
--   lock take:  lockBar:SetMinMaxValues(0, durObj:GetTotalDuration())
--   every tick: lockBar:SetValue(durObj:GetRemainingDuration())
-- No hook is involved: the button's private mixin runs in the forbidden
-- partition and holds the bar's forbidden object table, so neither a
-- per-object hook nor a method-table hook on SetTimerDuration ever fires.
--
-- Assignment: the button writes a zero-span duration only when its slot is
-- cleared (AuraButton ClearAuraInstance); assign and update both go straight
-- to SetTimeFromEnd. So the TOTAL duration is exactly zero while the slot is
-- clear and at least one second for any live aura, and a secret number's
-- zero-ness is observable (C_StringUtil.TruncateWhenZero through a scratch
-- FontString; the unitframesz launder). Zero -> non-zero on a tick is a fresh
-- instance: take the lock. Refreshes and extensions never pass through zero
-- and keep it; a pandemic recast keeps it too, and the geometry then shows
-- the longer of the two cadences. The launder must NOT see the remaining
-- time: TruncateWhenZero floors to an integer, so remaining reads "zero" for
-- the whole last second of an aura, and an extension landing in that second
-- re-took the lock at the extended (shorter) total.
--
-- "Original" is the total of a FRESH instance (elapsed floors to zero on the
-- flip tick, so it was applied within the last second) and stays until the
-- next fresh instance. An instance that arrives already running (target
-- swapped back to a unit whose aura was extended earlier; the lock enabled
-- with an aura already up) is skipped: the previous lock stays, or the bar
-- rests (engine fill) until a fresh application. The base duration is a
-- property of the spell, so one fresh take is right for every target; there
-- is no re-take on target/focus swaps.
--
-- Everything fails open: any error rests the lock bar (full), which shows the
-- engine's fill unchanged, until the next Configure or regen re-arms it.
-- Records never store tree references beyond the duration object.
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = SAU.Engine
local Record = Engine.Record
local SetResult = Engine._SetResult
local SafeToString = Engine._SafeToString

local Cadence = {}
SAU.Cadence = Cadence

local records = {}   -- [poolEntry] = rec (one per wired container)
local active = {}    -- [poolEntry] = rec (driver set)
local driver
local eventFrame

local TAKE_LOG_MAX = 12

--------------------------------------------------------------------------------
-- Lock bar
--------------------------------------------------------------------------------

--- Creates the per-entry lock bar under the entry's visual frame. Alpha 0 and
-- never hidden: a hidden StatusBar stops laying out its fill texture, and the
-- clips anchored to that texture would freeze.
function Cadence.CreateLockBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetFrameLevel(parent:GetFrameLevel() + 1)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetAlpha(0)
    bar:EnableMouse(false)
    bar:SetSize(32, 32)
    bar:SetPoint("CENTER", parent, "CENTER", 0, 0)
    return bar
end

-- Rest = full, in both modes, and no lock held. Deplete: barClip spans the
-- whole bar and the engine's fill shows through. Fill: the lock bar is
-- reverse-filled, its texture spans the bar, and lockClip (bar left edge to
-- texture left edge) is zero-width. Presence is forgotten too, so the next
-- tick re-derives it and takes the lock if an aura is up.
local function SetRest(rec)
    local bar = rec and rec.lockBar
    if not bar then return end
    pcall(bar.SetMinMaxValues, bar, 0, 1)
    pcall(bar.SetValue, bar, 1)
    local mirror = rec.entry and rec.entry.lockMirror
    if mirror then
        pcall(mirror.SetMinMaxValues, mirror, 0, 1)
        pcall(mirror.SetValue, mirror, 1)
    end
    rec.taken = false
    rec.present = nil
end

--------------------------------------------------------------------------------
-- Zero launder (port of unitframesz/engine.lua isZeroAmount)
--------------------------------------------------------------------------------

local zeroScratchFS

local function EnsureZeroScratch()
    if zeroScratchFS then return zeroScratchFS end
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, -360)
    holder:Hide()
    zeroScratchFS = holder:CreateFontString(nil, "BACKGROUND")
    zeroScratchFS:SetPoint("CENTER", holder, "CENTER", 0, 0)
    -- A font must be set before any SetText on a template-less FontString.
    zeroScratchFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    return zeroScratchFS
end

local function IsBlank(text) return not text end

-- true = floors to zero, false = at least one, nil = route unavailable.
-- Never == on the GetText result (a secret string throws on compare); the
-- FontString round-trip turns the blank into a plain nil.
local function IsZeroAmount(v)
    if not (_G.C_StringUtil and C_StringUtil.TruncateWhenZero) then return nil end
    local okT, trunc = pcall(C_StringUtil.TruncateWhenZero, v)
    if not okT then return nil end
    if not (issecretvalue and issecretvalue(trunc)) then
        return (trunc == nil or trunc == "") and true or false
    end
    local scratch = EnsureZeroScratch()
    if scratch.ClearText then scratch:ClearText() end
    if not pcall(scratch.SetText, scratch, trunc) then return nil end
    local okG, text = pcall(scratch.GetText, scratch)
    if not okG then return nil end
    local okB, blank = pcall(IsBlank, text)
    if not okB then return nil end
    return blank and true or false
end

--------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------

local function Deactivate(entry, rec)
    active[entry] = nil
    SetRest(rec)
end

local function Fail(entry, rec, err)
    rec.failed = SafeToString(err)
    Deactivate(entry, rec)
    local id = entry.occupantId and ("t" .. entry.occupantId) or ("entry" .. tostring(entry.index))
    SetResult("cadence." .. id, "FAILED: " .. rec.failed)
    Record("cadence-fail", id .. " " .. rec.failed)
end

-- The lock bar's max becomes the duration object's current total. Called on
-- a zero -> non-zero step of the total whose elapsed time floors to zero (a
-- fresh instance).
local function TakeLock(entry, rec, durObj)
    local bar = rec.lockBar
    if not (bar and durObj) then return false end
    local ok, total = pcall(durObj.GetTotalDuration, durObj)
    if ok then
        local mirror = entry.lockMirror
        if mirror then pcall(mirror.SetMinMaxValues, mirror, 0, total) end
        ok, total = pcall(bar.SetMinMaxValues, bar, 0, total)
    end
    if not ok then
        Fail(entry, rec, total)
        return false
    end
    rec.taken = true
    rec.takeCount = (rec.takeCount or 0) + 1
    local log = rec.takeLog
    if not log then
        log = {}
        rec.takeLog = log
    end
    log[#log + 1] = GetTime()
    if #log > TAKE_LOG_MAX then table.remove(log, 1) end
    return true
end

-- One evaluation. Presence (total floors to zero or not) is read first: a
-- zero -> non-zero step is a fresh instance and takes the lock before the
-- value lands. A dead launder means assignment is undetectable, so the lock
-- rests rather than freeze on a guess (fail open).
local function Tick(entry, rec)
    local durObj, bar = rec.durObj, rec.lockBar
    if not (durObj and bar) then
        Deactivate(entry, rec)
        return false
    end
    local ok, total = pcall(durObj.GetTotalDuration, durObj)
    if not ok then
        Fail(entry, rec, total)
        return false
    end
    local zero = IsZeroAmount(total)
    if zero == nil then
        rec.launderDead = true
        Fail(entry, rec, "zero launder unavailable")
        return false
    end
    rec.launderDead = nil
    local present = not zero
    if present and not rec.present then
        rec.presentFlips = (rec.presentFlips or 0) + 1
        -- Only a fresh instance carries the base duration. An instance that
        -- arrives already running (target swapped back to a unit whose aura
        -- was extended earlier) keeps the previous lock, or leaves the bar
        -- at rest until a fresh application shows up. Fresh = elapsed floors
        -- to zero (applied within the last second). An unreadable elapsed
        -- counts as fresh: taking is the fail-open side.
        local okE, elapsed = pcall(durObj.GetElapsedDuration, durObj)
        local stale = okE and IsZeroAmount(elapsed) == false
        if stale then
            rec.staleSkips = (rec.staleSkips or 0) + 1
        elseif not TakeLock(entry, rec, durObj) then
            return false
        end
    end
    rec.present = present

    local v
    ok, v = pcall(durObj.GetRemainingDuration, durObj)
    if not ok then
        Fail(entry, rec, v)
        return false
    end
    local mirror = entry.lockMirror
    if mirror then pcall(mirror.SetValue, mirror, v) end
    ok, v = pcall(bar.SetValue, bar, v)
    if not ok then
        Fail(entry, rec, v)
        return false
    end
    rec.tickCount = (rec.tickCount or 0) + 1
    return true
end

local function DriverOnUpdate()
    if not next(active) then
        driver:Hide()
        return
    end
    for entry, rec in pairs(active) do
        Tick(entry, rec)
    end
end

local function Activate(entry, rec)
    if not (rec.enabled and rec.durObj and rec.lockBar) then
        return false
    end
    active[entry] = rec
    if not driver then
        driver = CreateFrame("Frame")
        driver:Hide()
        driver:SetScript("OnUpdate", DriverOnUpdate)
    end
    driver:Show()
    return true
end

-- Re-arm anything that failed during the fight; the first tick re-derives
-- presence and takes the lock if an aura is up.
local function OnRegenEnabled()
    for entry, rec in pairs(records) do
        if rec.failed and not active[entry] then
            rec.failed = nil
            Activate(entry, rec)
        end
    end
end

local function EnsureEvents()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", OnRegenEnabled)
end

--------------------------------------------------------------------------------
-- Wiring and configuration
--------------------------------------------------------------------------------

--- Called from Engine.WireButton (inside initializeFrame) once the bar
-- element exists. Starts a new record for this container.
function Cadence.OnWire(entry)
    records[entry] = {
        entry = entry,
        lockBar = entry.lockBar,
        mode = "deplete",
        takeCount = 0,
        tickCount = 0,
        presentFlips = 0,
    }
    active[entry] = nil
end

-- Asks the Scoot-bound bar for the duration object it was timed with. Legal
-- only under the structural gate (Configure's caller), where the tree is
-- readable. A new object (rebuilt bar) drops the held lock; the same object
-- keeps it.
local function GrabDuration(rec, state)
    local barFill
    for _, elem in ipairs(state and state.elements or {}) do
        if elem.type == "bar" then
            barFill = elem.barFill
            break
        end
    end
    if not barFill then
        rec.grab = "no bar element"
        return
    end
    local ok, d = pcall(barFill.GetTimerDuration, barFill)
    if ok and type(d) == "userdata" then
        if rec.durObj ~= d then
            rec.durObj = d
            rec.present = nil
            rec.taken = false
        end
        local okS, secret = pcall(d.HasSecretValues, d)
        rec.grab = "ok secret=" .. tostring(okS and secret)
    else
        rec.grab = "FAILED: " .. SafeToString(d)
    end
end

--- Runs under the structural gate, right after BindForMode.
function Cadence.Configure(trackerId, tracker, state)
    local entry = state and state.entry
    if not entry then return end
    local db = SAU.GetDB(trackerId)
    local fillMode = db and db.barFillMode == "fill"
    local lockBar = entry.lockBar
    if lockBar then
        -- Fill mode reads the lock bar from the right: its texture is the
        -- remaining share, so the span from the bar's left edge to the
        -- texture's left edge is the elapsed share (see regions.lua).
        pcall(lockBar.SetReverseFill, lockBar, fillMode and true or false)
    end

    local rec = records[entry]
    if not rec then
        SetRest({ lockBar = lockBar })
        return
    end

    rec.lockBar = lockBar
    rec.mode = fillMode and "fill" or "deplete"
    rec.unit = tracker and tracker.unit or nil
    local vis = tracker and db and SAU.ResolveVisibility(tracker, db) or nil
    rec.enabled = (vis and vis.showBar and db.barLockCadence == true) and true or false
    if not rec.enabled then
        Deactivate(entry, rec)
        return
    end

    GrabDuration(rec, state)
    rec.failed = nil
    EnsureEvents()
    if Activate(entry, rec) then
        Tick(entry, rec)
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- The entry's container was retired; a new container gets a new record from
-- OnWire.
function Cadence.OnRetire(entry)
    Deactivate(entry, records[entry])
    records[entry] = nil
end

--- The tracker released its entry (container parked). The record survives:
-- a revive-on-content-match keeps the same button, and Configure re-enables
-- it at the next claim.
function Cadence.OnRelease(entry)
    local rec = records[entry]
    if rec then rec.enabled = false end
    Deactivate(entry, rec)
end

--------------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------------

-- Plain-or-"secret" rendering for the dump; never lets a secret reach a
-- string operation.
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return "secret" end
    return tostring(v)
end

function Cadence.DebugInfo(trackerId)
    local entry = Engine._byTracker[trackerId]
    if not entry then return nil, "no pool entry" end
    local rec = records[entry]
    if not rec then return nil, "no cadence record (bar not wired yet)" end
    local state = SAU._activeStates and SAU._activeStates[trackerId]
    local lines = {
        "enabled=" .. tostring(rec.enabled),
        "grab=" .. tostring(rec.grab),
        "durObj=" .. tostring(rec.durObj ~= nil),
        "present=" .. tostring(rec.present) .. " presentFlips=" .. tostring(rec.presentFlips)
            .. " launderDead=" .. tostring(rec.launderDead),
        "takeCount=" .. tostring(rec.takeCount) .. " staleSkips=" .. tostring(rec.staleSkips or 0)
            .. " tickCount=" .. tostring(rec.tickCount),
        "mode=" .. tostring(rec.mode) .. " unit=" .. tostring(rec.unit),
        "geometry=" .. tostring(state and state.cadenceGeometry),
        "taken=" .. tostring(rec.taken),
        "active=" .. tostring(active[entry] ~= nil),
        "driverShown=" .. tostring(driver ~= nil and driver:IsShown()),
        "failed=" .. tostring(rec.failed),
        "lockBar=" .. tostring(rec.lockBar ~= nil),
    }
    -- Last takes as seconds before now: every take after the first should
    -- follow a visible gap in the aura (expiry or a target without it).
    if rec.takeLog and #rec.takeLog > 0 then
        local now = GetTime()
        local parts = {}
        for _, t in ipairs(rec.takeLog) do
            parts[#parts + 1] = ("-%.1fs"):format(now - t)
        end
        table.insert(lines, "takes=" .. table.concat(parts, " "))
    end
    local bar = rec.lockBar
    if bar then
        -- Scoot-owned frame: its own size, alpha and level are plain. The
        -- fill texture's width derives from secret values and prints "secret".
        local w, h = bar:GetSize()
        table.insert(lines, ("lockBarSize=%s x %s alpha=%s level=%s reverse=%s visible=%s"):format(
            Plain(w), Plain(h), Plain(bar:GetAlpha()), Plain(bar:GetFrameLevel()),
            tostring(bar:GetReverseFill()), tostring(bar:IsVisible())))
        local tex = bar:GetStatusBarTexture()
        local okW, tw = pcall(function() return tex and tex:GetWidth() end)
        table.insert(lines, "lockTexWidth=" .. (okW and Plain(tw) or ("ERR " .. Plain(tw))))
    end
    return lines
end

--- Debug probes on a tracker's lock bar:
--   alpha <a>   show the lock bar itself, raised above the button tree
--               (a > 0) or put back (0). It sits exactly on the styled bar.
--   mirror <y>  a separate white bar y px above the styled bar (default 10),
--               fed the same two values as the lock bar and taking no part in
--               the clip geometry; "mirror off" hides it.
--   set <v>     force the lock bar to v on a 0..1 range (geometry probe).
function Cadence.DebugSet(trackerId, what, value)
    local entry = Engine._byTracker[trackerId]
    if not entry then return false, "no pool entry for tracker t" .. tostring(trackerId) end
    local bar = entry.lockBar
    if not bar then return false, "no lock bar on tracker t" .. tostring(trackerId) end
    if what == "alpha" then
        local a = tonumber(value) or 0
        bar:SetAlpha(a)
        local base = entry.visual and entry.visual:GetFrameLevel() or 0
        bar:SetFrameLevel(a > 0 and (base + 40) or (base + 1))
        return true
    end
    if what == "mirror" then
        local mirror = entry.lockMirror
        if value == "off" or value == "0" then
            if mirror then mirror:Hide() end
            return true
        end
        local dy = tonumber(value) or 10
        if not mirror then
            mirror = CreateFrame("StatusBar", nil, entry.visual)
            mirror:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            mirror:GetStatusBarTexture():SetVertexColor(1, 1, 1, 0.9)
            mirror:EnableMouse(false)
            entry.lockMirror = mirror
        end
        local w, h = bar:GetSize()
        mirror:SetSize(w, h)
        mirror:SetReverseFill(bar:GetReverseFill())
        mirror:ClearAllPoints()
        mirror:SetPoint("BOTTOM", bar, "TOP", 0, dy)
        mirror:SetFrameLevel((entry.visual and entry.visual:GetFrameLevel() or 0) + 40)
        -- Start from the lock bar's rest state; the next take/tick feeds it.
        -- With a lock already held, seed the max from the duration object's
        -- current total (the lock's own max is secret and cannot be copied);
        -- the next fresh application aligns the two exactly.
        mirror:SetMinMaxValues(0, 1)
        mirror:SetValue(1)
        local rec = records[entry]
        if rec and rec.taken and rec.durObj then
            pcall(function() mirror:SetMinMaxValues(0, rec.durObj:GetTotalDuration()) end)
        end
        mirror:Show()
        return true
    end
    -- A forced value only holds while the driver is not ticking this entry.
    Deactivate(entry, records[entry])
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(tonumber(value) or 1)
    return true
end
