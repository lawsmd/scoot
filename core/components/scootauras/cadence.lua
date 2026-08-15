-- scootauras/cadence.lua - "Lock drain to original duration" for bar trackers
--
-- The engine binds elem.barFill through SetDurationBar and drives its fill as
-- remaining / current duration; when a mechanic extends the aura, Blizzard
-- reports the extended value as the new total, so the bar refills and its
-- drain speed changes. This module keeps a second, invisible StatusBar (the
-- "lock bar", entry.lockBar, outside every button tree) at
-- remaining / originalDuration, and regions.lua composes the two
-- geometrically (deplete: barFill clipped to the lock bar's fill; fill: a
-- lock-clipped overlay unioned with barFill). No Lua ever compares a duration.
--
-- The seam: Blizzard's CustomAuraButton ApplyDurationBar calls
-- statusBar:SetTimerDuration(auraDuration, ...) on the bound bar on every aura
-- assignment, update, and clear. InitializeInboundScriptObject only adds
-- forbidden aspects to that same object, so a hooksecurefunc installed on our
-- barFill before binding receives the button's private duration object. The
-- lock bar is then ticked with durObj:EvaluateRemainingDuration(curve), an
-- engine-side evaluation that accepts secret internals; the curve
-- (0,0)->(orig,1) yields remaining/orig, and the StatusBar saturates above 1.
--
-- The original duration must be a plain number to build the curve. It comes
-- from the tracker's override (barLockDuration) or from a value learned per
-- spell the first time the aura is assigned while its duration is readable
-- (outside restricted content). Unknown original = lock bar at rest = today's
-- behavior. The hook handler never touches its `self` (a denied tree member
-- while auras are secret); records never store tree references.
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = SAU.Engine
local Record = Engine.Record
local SetResult = Engine._SetResult
local SafeToString = Engine._SafeToString

local Cadence = {}
SAU.Cadence = Cadence

local LINEAR = (Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear) or 0

local records = {}   -- [poolEntry] = rec (one per wired container)
local active = {}    -- [poolEntry] = rec (driver set)
local curves = { deplete = {}, fill = {} }   -- [mode][orig*100] = LuaCurveObject
local driver

Cadence._records = records
Cadence._active = active

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

--------------------------------------------------------------------------------
-- Curves and rest values
--------------------------------------------------------------------------------

local function GetCurve(mode, orig)
    local cache = curves[mode] or curves.deplete
    local key = math.floor(orig * 100 + 0.5)
    local curve = cache[key]
    if curve then return curve end
    curve = C_CurveUtil.CreateCurve()
    curve:SetType(LINEAR)
    if mode == "fill" then
        curve:AddPoint(0, 1)
        curve:AddPoint(orig, 0)
    else
        curve:AddPoint(0, 0)
        curve:AddPoint(orig, 1)
    end
    cache[key] = curve
    return curve
end

-- Neutral value: full for deplete (intersection), empty for fill (union).
local function RestValue(mode)
    return (mode == "fill") and 0 or 1
end

local function SetRest(rec)
    if rec and rec.lockBar then
        pcall(rec.lockBar.SetValue, rec.lockBar, RestValue(rec.mode))
    end
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

-- One evaluation. Returns true on success; on any error the tracker's cadence
-- rests (fail open: the visible bar shows the engine's fill) until the next
-- hook call re-arms it.
local function Tick(entry, rec)
    local durObj, curve, bar = rec.durObj, rec.curve, rec.lockBar
    if not (durObj and curve and bar) then
        Deactivate(entry, rec)
        return false
    end
    local ok, v = pcall(durObj.EvaluateRemainingDuration, durObj, curve)
    if ok then
        ok, v = pcall(bar.SetValue, bar, v)
    end
    if not ok then
        Fail(entry, rec, v)
        return false
    end
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
    if not (rec.enabled and rec.curve and rec.durObj and rec.lockBar) then
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

--------------------------------------------------------------------------------
-- Original duration
--------------------------------------------------------------------------------

local function ResolveOriginal(tracker, db)
    local override = tonumber(db and db.barLockDuration) or 0
    if override > 0 then
        return override, "override"
    end
    local learned = tracker and SAU.GetLearnedDuration(tracker.spellId)
    if learned then
        return learned, "learned"
    end
    return nil, nil
end

--------------------------------------------------------------------------------
-- Hook (installed inside initializeFrame, before SetDurationBar)
--------------------------------------------------------------------------------

local function HandleDuration(entry, rec, durObj)
    rec.hookCount = (rec.hookCount or 0) + 1
    rec.durObj = durObj
    rec.failed = nil

    -- Learn the original duration while it is readable. Only a FRESH
    -- assignment (previous readable total was zero, or nothing seen yet since
    -- wire) reports the aura's real duration; an update may carry an extended
    -- one. Never IsZero() on aura duration objects.
    local readable = false
    if durObj and durObj.HasSecretValues then
        local okS, secret = pcall(durObj.HasSecretValues, durObj)
        readable = okS and secret == false
    end
    if readable then
        local okT, total = pcall(durObj.GetTotalDuration, durObj)
        if okT and type(total) == "number" and not issecretvalue(total) then
            local fresh = (rec.lastTotal == nil) or (rec.lastTotal == 0)
            if total > 0 and fresh then
                local tracker = entry.occupantId and SAU.GetTracker(entry.occupantId)
                if tracker then
                    SAU.SetLearnedDuration(tracker.spellId, total)
                end
            end
            rec.lastTotal = total
            if total == 0 then
                -- Cleared (or a permanent aura): nothing to pace.
                Deactivate(entry, rec)
                return
            end
        else
            rec.lastTotal = false
        end
    else
        -- Unreadable: keep driving. Every visible part is inside the button
        -- tree and hides with it, so a stale lock value while the aura is
        -- absent has no visible effect.
        rec.lastTotal = false
    end

    if Activate(entry, rec) then
        Tick(entry, rec)
    end
end

function Cadence.OnTimerDuration(entry, seq, durObj)
    local rec = records[entry]
    if not rec or rec.seq ~= seq then return end   -- stale container's hook
    local ok, err = pcall(HandleDuration, entry, rec, durObj)
    if not ok then
        Fail(entry, rec, err)
    end
end

--- Called from Engine.WireButton (inside initializeFrame) with the freshly
-- created bar element. Installs the SetTimerDuration hook and starts a new
-- record for this container.
function Cadence.OnWire(entry, barElem)
    local seq = entry.slotSeq
    local rec = {
        seq = seq,
        lockBar = entry.lockBar,
        mode = "deplete",
        hookCount = 0,
    }
    records[entry] = rec
    active[entry] = nil

    local barFill = barElem and barElem.barFill
    local ok, err = false, "no barFill"
    if barFill then
        ok, err = pcall(hooksecurefunc, barFill, "SetTimerDuration", function(_, durObj)
            Cadence.OnTimerDuration(entry, seq, durObj)
        end)
    end
    rec.hooked = ok and true or false
    local id = entry.occupantId and ("t" .. entry.occupantId) or ("entry" .. tostring(entry.index))
    SetResult("cadence.hook." .. id, ok and "ok" or ("FAILED: " .. SafeToString(err)))
end

--------------------------------------------------------------------------------
-- Configuration (runs under the structural gate, right after BindForMode)
--------------------------------------------------------------------------------

function Cadence.Configure(trackerId, tracker, state)
    local entry = state and state.entry
    if not entry then return end
    local db = SAU.GetDB(trackerId)
    local fillMode = db and db.barFillMode == "fill"
    local rec = records[entry]
    if not rec then
        -- No hook for this container (bar not wired, or the hook failed):
        -- keep the lock bar neutral for the bound mode.
        if entry.lockBar then
            pcall(entry.lockBar.SetValue, entry.lockBar, RestValue(fillMode and "fill" or "deplete"))
        end
        return
    end

    rec.lockBar = entry.lockBar
    rec.mode = fillMode and "fill" or "deplete"
    local vis = tracker and db and SAU.ResolveVisibility(tracker, db) or nil
    rec.enabled = (vis and vis.showBar and db.barLockCadence == true) and true or false
    if rec.enabled then
        rec.orig, rec.origSource = ResolveOriginal(tracker, db)
        rec.curve = rec.orig and GetCurve(rec.mode, rec.orig) or nil
    else
        rec.orig, rec.origSource, rec.curve = nil, nil, nil
    end

    if not rec.enabled or not rec.curve then
        Deactivate(entry, rec)
        return
    end
    if Activate(entry, rec) then
        Tick(entry, rec)
    else
        SetRest(rec)
    end
end

--- A learned value arrived for spellId: re-derive every enabled record of that
-- spell that has no override. Scoot-only work, legal in combat.
function Cadence.OnLearned(spellId)
    for entry, rec in pairs(records) do
        local trackerId = entry.occupantId
        local tracker = trackerId and SAU.GetTracker(trackerId)
        if tracker and tracker.spellId == spellId and rec.enabled then
            local db = SAU.GetDB(trackerId)
            local override = tonumber(db and db.barLockDuration) or 0
            if override <= 0 then
                rec.orig, rec.origSource = ResolveOriginal(tracker, db)
                rec.curve = rec.orig and GetCurve(rec.mode, rec.orig) or nil
                if Activate(entry, rec) then
                    Tick(entry, rec)
                end
            end
        end
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
-- a revive-on-content-match keeps the same button and hook.
function Cadence.OnRelease(entry)
    Deactivate(entry, records[entry])
end

--------------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------------

function Cadence.DebugInfo(trackerId)
    local entry = Engine._byTracker[trackerId]
    if not entry then return nil, "no pool entry" end
    local rec = records[entry]
    if not rec then return nil, "no cadence record (bar not wired yet)" end
    local lines = {
        "hooked=" .. tostring(rec.hooked),
        "hookCount=" .. tostring(rec.hookCount),
        "enabled=" .. tostring(rec.enabled),
        "mode=" .. tostring(rec.mode),
        "orig=" .. tostring(rec.orig) .. " (" .. tostring(rec.origSource) .. ")",
        "curve=" .. tostring(rec.curve ~= nil),
        "durObj=" .. tostring(rec.durObj ~= nil),
        "lastTotal=" .. tostring(rec.lastTotal),
        "active=" .. tostring(active[entry] ~= nil),
        "failed=" .. tostring(rec.failed),
        "lockBar=" .. tostring(rec.lockBar ~= nil),
    }
    return lines
end

--- Forces the lock bar's value (geometry probe) or its alpha (visibility
-- probe) from the debug command.
function Cadence.DebugSet(trackerId, what, value)
    local entry = Engine._byTracker[trackerId]
    local bar = entry and entry.lockBar
    if not bar then return false, "no lock bar" end
    if what == "alpha" then
        bar:SetAlpha(tonumber(value) or 0)
        return true
    end
    -- A forced value only holds while the driver is not ticking this entry.
    Deactivate(entry, records[entry])
    bar:SetValue(tonumber(value) or 1)
    return true
end
