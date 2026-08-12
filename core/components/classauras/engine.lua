-- classauras/engine.lua - AuraContainer slot engine (12.1)
--
-- The engine owns aura acquisition and display: one AuraContainer per aura,
-- parented inside the Scoot per-aura frame, one AddAuraSlot whose button hosts
-- every visual element. Aura matching (spell-ID candidate filters) and display
-- (duration bars, ticking text, application counts) run engine-side, so the
-- addon never reads aura data and the display keeps working while aura
-- information is secret.
--
-- Access contract: the button tree is untouchable from addon code while auras
-- are secret, so all structural/styling work funnels through ApplyAll, which
-- either runs immediately (out of combat, auras readable) or queues per aura
-- and flushes on PLAYER_REGEN_ENABLED. The Scoot frame itself (position,
-- scale, alpha, shown) is addon-owned and always legal to touch (Tier 1).
local addonName, addon = ...

local CA = addon.ClassAuras
local Engine = {}
CA.Engine = Engine

local GetDB = CA._GetDB

-- [auraId] = { container, button, wired, desiredEnabled, enabledDirty }
local entries = {}

-- Apply requests that arrived while the button tree was untouchable.
local pendingApply = {}

--------------------------------------------------------------------------------
-- Telemetry (mirrors the unitframes auracontainer pilot's Record/SetResult)
--------------------------------------------------------------------------------

local results = {}   -- [key] = latest observation string
local log = {}       -- ring of { seq, tag, detail }
local logSeq = 0
local LOG_MAX = 64

local function SafeToString(v)
    if issecretvalue(v) then return "<SECRET>" end
    local ok, s = pcall(tostring, v)
    return ok and s or "<tostring failed>"
end

local function Record(tag, detail)
    logSeq = logSeq + 1
    log[(logSeq % LOG_MAX) + 1] = { seq = logSeq, tag = tag, detail = detail }
end

local function SetResult(key, value)
    results[key] = value
end

Engine._results = results
Engine._log = log
Engine._entries = entries
Engine._pendingApply = pendingApply

--------------------------------------------------------------------------------
-- Gates and predicates
--------------------------------------------------------------------------------

function Engine.IsEngineDriven(aura)
    if not aura then return false end
    return aura.engineDriven or false
end

function Engine.IsWired(auraId)
    local entry = entries[auraId]
    return (entry and entry.wired) or false
end

-- Container/slot/region work touches the button tree, which carries
-- DenyTaintedAccessWhenAurasAreSecret; do it only in a fully open window.
function Engine.CanDoStructuralWork()
    if InCombatLockdown() then return false end
    if addon.AurasSecretNow and addon.AurasSecretNow() then return false end
    return true
end

--------------------------------------------------------------------------------
-- Candidate filters
--------------------------------------------------------------------------------

-- CDM is a data source: fold every spell ID Blizzard links to this aura's CDM
-- entry into the include set, so the engine matches variants we never see.
local CDM_CATEGORIES = (function()
    local cat = Enum and Enum.CooldownViewerCategory
    if cat then
        local out = {}
        for _, v in pairs(cat) do
            if type(v) == "number" then table.insert(out, v) end
        end
        table.sort(out)
        if #out > 0 then return out end
    end
    return { 0, 1, 2, 3 } -- Essential, Utility, TrackedBuff, TrackedBar
end)()

local function ExpandFromCDM(include, lookupSpellId)
    if not lookupSpellId or not C_CooldownViewer then return end
    if not C_CooldownViewer.GetCooldownViewerCategorySet
        or not C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return
    end
    for _, category in ipairs(CDM_CATEGORIES) do
        local ok, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
        if ok and type(cooldownIDs) == "table" and not issecretvalue(cooldownIDs) then
            for _, cooldownID in ipairs(cooldownIDs) do
                if not issecretvalue(cooldownID) then
                    local iok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                    if iok and type(info) == "table" and not issecretvalue(info) then
                        local sid = not issecretvalue(info.spellID) and info.spellID or nil
                        local oid = not issecretvalue(info.overrideSpellID) and info.overrideSpellID or nil
                        if sid == lookupSpellId or oid == lookupSpellId then
                            if sid then include[sid] = true end
                            if oid then include[oid] = true end
                            local linked = info.linkedSpellIDs
                            if type(linked) == "table" and not issecretvalue(linked) then
                                for _, lid in ipairs(linked) do
                                    if type(lid) == "number" and not issecretvalue(lid) then
                                        include[lid] = true
                                    end
                                end
                            end
                            return
                        end
                    end
                end
            end
        end
    end
end

local function BuildCandidateFilters(aura)
    local include = { [aura.auraSpellId] = true }
    for _, linkedId in ipairs(aura.linkedSpellIds or {}) do
        include[linkedId] = true
    end
    pcall(ExpandFromCDM, include, aura.cdmSpellId or aura.auraSpellId)
    local count = 0
    for _ in pairs(include) do count = count + 1 end
    SetResult("filters." .. aura.id, count .. " include IDs")
    return { includeSpellIDs = include }
end

Engine._BuildCandidateFilters = BuildCandidateFilters

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

-- Creates the AuraContainer + slot for an aura; the slot's initializeFrame
-- wires all visual regions (regions.lua). Idempotent: returns the existing
-- entry when already built. Caller must hold the structural-work gate.
local function EnsureBuilt(aura)
    local state = CA._activeAuras[aura.id]
    if not state or not state.container then return nil end

    local entry = entries[aura.id]
    if entry then return entry end

    local scootFrame = state.container
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, scootFrame, "CustomAuraContainerTemplate")
    if not ok or not container then
        SetResult("build." .. aura.id .. ".container", "FAILED: " .. SafeToString(container))
        Record("build-fail", aura.id)
        return nil
    end
    SetResult("build." .. aura.id .. ".container", "ok")

    pcall(container.SetFrameLevel, container, scootFrame:GetFrameLevel() + 5)
    local uok, uerr = pcall(container.SetUnit, container, aura.unit)
    SetResult("build." .. aura.id .. ".setunit", uok and ("ok: " .. tostring(aura.unit)) or ("FAILED: " .. SafeToString(uerr)))

    entry = { container = container }
    entries[aura.id] = entry

    local slotOk, buttonOrErr = pcall(container.AddAuraSlot, container, aura.id, aura.filter, {
        candidateFilters = BuildCandidateFilters(aura),
        initializeFrame = function(button)
            entry.button = button
            local wok, werr = pcall(Engine.WireButton, aura, state, entry, button)
            entry.wired = wok and true or false
            SetResult("wire." .. aura.id, wok and "ok" or ("FAILED: " .. SafeToString(werr)))
            Record(wok and "wired" or "wire-fail", aura.id)
        end,
    })
    if not slotOk then
        SetResult("build." .. aura.id .. ".slot", "FAILED: " .. SafeToString(buttonOrErr))
        Record("slot-fail", aura.id)
        return entry
    end
    SetResult("build." .. aura.id .. ".slot", "ok")
    if not entry.button and buttonOrErr then
        -- AddAuraSlot returns the button; initializeFrame normally stored it already.
        entry.button = buttonOrErr
    end
    Record("built", aura.id)
    return entry
end

--------------------------------------------------------------------------------
-- Enabled state
--------------------------------------------------------------------------------

local function ApplyEnabledState(aura, entry, enabled)
    entry.desiredEnabled = enabled
    if not entry.container then return end
    local ok = pcall(entry.container.SetEnabled, entry.container, enabled)
    entry.enabledDirty = not ok
    if not ok then
        Record("enable-deferred", aura.id .. "=" .. tostring(enabled))
    end
end

-- Tier 1 entry: safe to call any time. When the container does not exist yet
-- there is nothing to disable (zero-touch: nothing was built).
function Engine.SetEnabledState(aura, enabled)
    local entry = entries[aura.id]
    if not entry then return end
    ApplyEnabledState(aura, entry, enabled)
end

--------------------------------------------------------------------------------
-- Apply (Tier 2) and queueing
--------------------------------------------------------------------------------

-- Full build + styling pass for one aura. Gated: queues itself when the
-- button tree is untouchable and re-runs on the regen flush.
function Engine.ApplyAll(aura)
    local state = CA._activeAuras[aura.id]
    if not state then return end

    if not Engine.CanDoStructuralWork() then
        pendingApply[aura.id] = true
        Record("apply-queued", aura.id)
        return
    end

    local entry = EnsureBuilt(aura)
    if not entry or not entry.wired then return end

    ApplyEnabledState(aura, entry, true)

    -- Static art first, then engine bindings, then fonts/colors (text color is
    -- re-applied after binding on purpose), then geometry.
    CA._ApplyIconMode(aura, state)
    CA._ApplyIconShape(aura, state)
    CA._ApplyBorders(aura, state)
    CA._ApplyBarStyling(aura, state)
    Engine.BindForMode(aura, state)
    CA._ApplyTextStyling(aura, state)
    CA._LayoutElements(aura, state)
    if aura.anchorTo then
        CA._ApplyAnchorLinkage(aura, state)
    end
    -- Def-specific engine styling (DK dot art, Alter Time snapshot text
    -- placement). Runs inside the gate, so hooks may touch the button tree.
    if aura.engineApply then
        local hok, herr = pcall(aura.engineApply, aura, state, entry)
        SetResult("hook." .. aura.id .. ".engineApply", hok and "ok" or ("FAILED: " .. SafeToString(herr)))
    end
    Record("applied", aura.id)
end

function Engine.FlushPending()
    local queued = pendingApply
    pendingApply = {}
    Engine._pendingApply = pendingApply
    for auraId in pairs(queued) do
        local aura = CA._registry[auraId]
        if aura then Engine.ApplyAll(aura) end
    end
    for auraId, entry in pairs(entries) do
        if entry.enabledDirty then
            local aura = CA._registry[auraId]
            if aura then ApplyEnabledState(aura, entry, entry.desiredEnabled) end
        end
    end
    Engine.KickAll("regen")
end

--------------------------------------------------------------------------------
-- Kicks (containers bound to "target" do not self-refresh on retarget)
--------------------------------------------------------------------------------

local function KickEntry(auraId, entry, reason)
    if not entry.container then return end
    local ok, err = pcall(entry.container.UpdateAllAuras, entry.container)
    SetResult("kick." .. auraId, ok and ("ok (" .. reason .. ")") or ("FAILED (" .. reason .. "): " .. SafeToString(err)))
end

function Engine.KickUnit(unitToken, reason)
    for auraId, entry in pairs(entries) do
        local aura = CA._registry[auraId]
        if aura and aura.unit == unitToken then
            KickEntry(auraId, entry, reason or "unit")
        end
    end
end

function Engine.KickAll(reason)
    for auraId, entry in pairs(entries) do
        KickEntry(auraId, entry, reason or "all")
    end
end

--------------------------------------------------------------------------------
-- Shared helpers for regions.lua and the debug surface
--------------------------------------------------------------------------------

Engine._SafeToString = SafeToString
Engine._Record = Record
Engine._SetResult = SetResult
Engine._GetDB = GetDB
