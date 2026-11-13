-- scootauras/missingcast.lua - Click to cast on a missing-buff reminder
--
-- The reminder's content hangs off an engine-sized container, and its visual
-- is moved and resized in combat (Tier 1 restyles, group layout, the group
-- signal's re-anchor). A protected child or a protected frame anchored into
-- that tree would make every one of those frames implicitly protected and
-- block that work in lockdown: moving a frame would move the protected one.
--
-- So the click target is a SecureActionButton parented to UIParent and never
-- anchored to a Scoot frame: out of combat its rect is COPIED from the visual.
-- A visibility state driver hides it in combat and pet battles, so the combat
-- edge does not depend on Lua handler order. Lua owns only what it may set out
-- of combat: the rect, the spell attribute, and whether the mouse is on.
--
-- The mouse is on only while the buff is known to be missing from plain
-- state: the group verdict, or a player aura read while auras are not secret.
-- The content's own position is secret, so without that test the button
-- could sit over a reminder the geometry has pushed out of view and swallow
-- clicks meant for the world.
--
-- A Weapon Buff reminder uses the same button with no action type and a
-- target-slot attribute naming the bare hand. SecureActionButtonTemplate ends
-- every click with a targeting branch (SecureTemplates.lua, OnActionButtonClick):
-- while SpellCanTargetItem() is true, as it is with a poison, stone or oil
-- waiting for a weapon, it calls UseInventoryItem(target-slot), which applies
-- the held item to that weapon. With nothing held the click does nothing.
local addonName, addon = ...

local SAU = addon.ScootAuras

local MissingCast = {}
SAU.MissingCast = MissingCast

-- Above the content (visual + 2) and the container (visual + 5).
local LEVEL_BUMP = 20
local VISIBILITY_DRIVER = "[petbattle][combat] hide; show"

-- Aura id -> cast spell id, for buffs whose cast the Cooldown Manager catalog
-- does not link to the aura. Filled only for gaps found in play; the debug
-- window's cast= line names any that fail to resolve.
local CAST_FOR_AURA = {}

local function PlainNumber(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function PlainTrue(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    if not ok or (issecretvalue and issecretvalue(v)) then return false end
    return v == true
end

--- Whether the player can cast this id: known, and not a passive.
local function Castable(id)
    if type(id) ~= "number" then return false end
    local known = (C_SpellBook and PlainTrue(C_SpellBook.IsSpellKnown, id))
        or PlainTrue(IsPlayerSpell, id)
    if not known then return false end
    return not (C_Spell and PlainTrue(C_Spell.IsSpellPassive, id))
end

--------------------------------------------------------------------------------
-- Cast resolution
--------------------------------------------------------------------------------

-- Per tracker: { spellId, version, castId (false for none) }. Rebuilt when the
-- spell or the CDM catalog epoch moves, and when spells change (learned
-- talents do not bump the catalog epoch).
local castCache = {}

function MissingCast.InvalidateCasts()
    wipe(castCache)
end

addon.Events.On("ScootAurasMissingCast", "SPELLS_CHANGED", MissingCast.InvalidateCasts)

--- The spell id a click casts for this tracker, or nil. Order: the tracked id
-- itself, then every CDM alias of it (the catalog's base spell is usually the
-- cast and its linked ids the auras), then the manual table.
function MissingCast.CastSpellFor(trackerId, tracker)
    if not tracker or type(tracker.spellId) ~= "number" then return nil end
    local version = addon.AuraIds.GetVersion and addon.AuraIds.GetVersion() or 0
    local rec = castCache[trackerId]
    if rec and rec.spellId == tracker.spellId and rec.version == version then
        return rec.castId or nil
    end

    local castId = false
    if Castable(tracker.spellId) then
        castId = tracker.spellId
    else
        for _, id in ipairs(SAU.Missing.SpellIds(trackerId, tracker)) do
            if id ~= tracker.spellId and Castable(id) then
                castId = id
                break
            end
        end
    end
    if not castId then
        local manual = CAST_FOR_AURA[tracker.spellId]
        if manual and Castable(manual) then castId = manual end
    end

    castCache[trackerId] = { spellId = tracker.spellId, version = version, castId = castId }
    return castId or nil
end

--------------------------------------------------------------------------------
-- Missing test (plain state only)
--------------------------------------------------------------------------------

--- True when the player plainly lacks every id the reminder watches. False
-- whenever auras are secret: GetPlayerAuraBySpellID returns nothing then, and
-- nothing is not proof of absence.
local function PlayerPlainlyMissing(trackerId, tracker)
    if addon.AurasSecretNow() then return false end
    local fn = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if type(fn) ~= "function" then return false end
    for _, id in ipairs(SAU.Missing.SpellIds(trackerId, tracker)) do
        local ok, aura = pcall(fn, id)
        if not ok or aura ~= nil then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- The button
--------------------------------------------------------------------------------

-- trackerId -> entry for every button whose mouse is on: what the recheck
-- below walks.
local live = {}
local recheckTicker = nil

local function DisableButton(b)
    if b.mouseOn then
        b:EnableMouse(false)
        b.mouseOn = false
    end
    if b.trackerId then live[b.trackerId] = nil end
end

local function EnsureButton(entry)
    if entry.castButton then return entry.castButton end
    if InCombatLockdown() then return nil end
    -- UIParent is explicitly protected already (it parents Blizzard's own
    -- action bars), so this child changes nothing about it.
    local b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    b:SetSize(1, 1)
    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    b:RegisterForClicks("AnyUp")
    -- Fire on the release, as Blizzard's own buttons do for a mouse click.
    b:SetAttribute("useOnKeyDown", false)
    -- The action type is per kind; Sync writes it.
    b:EnableMouse(false)
    b.mouseOn = false
    RegisterStateDriver(b, "visibility", VISIBILITY_DRIVER)
    -- A visual hidden for any reason outside UpdateGate (its shell or group
    -- hidden, a teardown) takes the click target with it.
    entry.visual:HookScript("OnHide", function()
        if not InCombatLockdown() then DisableButton(b) end
    end)
    entry.castButton = b
    return b
end

--- Copies the visual's rect onto the button, in UIParent's coordinates. The
-- visual is Scoot-owned and plainly anchored, so its reads are numbers.
local function PlaceButton(b, visual)
    local left, bottom = visual:GetLeft(), visual:GetBottom()
    local w, h = visual:GetWidth(), visual:GetHeight()
    left, bottom, w, h = PlainNumber(left), PlainNumber(bottom), PlainNumber(w), PlainNumber(h)
    if not (left and bottom and w and h) or w <= 0 or h <= 0 then return false end
    local ratio = visual:GetEffectiveScale() / UIParent:GetEffectiveScale()
    left, bottom, w, h = left * ratio, bottom * ratio, w * ratio, h * ratio
    local r = b.rect
    if not (r and r[1] == left and r[2] == bottom and r[3] == w and r[4] == h) then
        b.rect = { left, bottom, w, h }
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        b:SetSize(w, h)
    end
    addon.Strata.MatchAnchor(b, visual, LEVEL_BUMP)
    return true
end

-- A group reflow can move the visual without a gate pass, and a cast that
-- lands hides the reminder by geometry alone. While any button takes clicks,
-- this re-reads both: the rect, and whether the buff is still plainly
-- missing (the group half is the group poll's job, through UpdateGate).
local RECHECK_SECONDS = 0.25

local function Recheck()
    if InCombatLockdown() then return end
    for trackerId, entry in pairs(live) do
        local b = entry.castButton
        local tracker = SAU.GetTracker(trackerId)
        local m = entry.missing
        local forced = m and m.forced
        -- The clip window's shown state is the gate's lit verdict.
        if not (b and tracker and m and m.clip:IsShown() and entry.visual:IsVisible()
            and (forced or PlayerPlainlyMissing(trackerId, tracker))
            and PlaceButton(b, entry.visual)) then
            if b then DisableButton(b) end
            live[trackerId] = nil
        end
    end
    if next(live) == nil and recheckTicker then
        recheckTicker:Cancel()
        recheckTicker = nil
    end
end

local results = {}

--- Turns the click target on or off for one reminder. Called at the end of
-- Missing.UpdateGate with that pass's verdicts. Out of combat only; in combat
-- the state driver has already hidden the button.
function MissingCast.Sync(trackerId, tracker, entry, lit, forced)
    if InCombatLockdown() then return end
    local function off(reason)
        results[trackerId] = reason
        local b = entry.castButton
        if b then DisableButton(b) end
    end

    local db = SAU.GetDB(trackerId)
    local kind = tracker and tracker.kind
    local weapon = kind == "weaponbuff"
    if not (weapon or kind == "missingbuff") then return off("not a reminder") end
    if not (db and db.clickToCast ~= false) then return off("setting off") end
    if not lit then return off("reminder hidden") end
    if SAU._isEditModeActive and SAU._isEditModeActive() then return off("edit mode") end
    if not entry.visual:IsVisible() then return off("visual hidden") end

    -- What the click does: a spell for a missing buff; for a weapon, no action
    -- of its own and the bare hand as the target slot. The hand is the one the
    -- icon shows, so with both bare the main hand comes first and the next
    -- WeaponBuff.Refresh moves the slot to the off hand.
    local actionType, castId, unit, slot = nil, nil, nil, nil
    if weapon then
        local missing
        missing, slot = SAU.WeaponBuff.Missing(tracker)
        if not (missing and slot) then return off("no bare weapon") end
    else
        castId = MissingCast.CastSpellFor(trackerId, tracker)
        if not castId then return off("no castable spell") end
        if not (forced or PlayerPlainlyMissing(trackerId, tracker)) then
            return off("buff not plainly missing")
        end
        actionType = "spell"
        -- A targeted buff (Earth Shield) follows normal targeting; everything
        -- else is a self or group-wide cast.
        unit = "player"
        if SAU.Missing.HasRangeSpell(trackerId, tracker) then unit = nil end
    end

    local b = EnsureButton(entry)
    if not b then return off("no button") end
    if not PlaceButton(b, entry.visual) then return off("no rect") end
    -- Every attribute is written for both kinds: a pool entry passes between
    -- them, and a stale spell or slot would ride along.
    if b:GetAttribute("type") ~= actionType then b:SetAttribute("type", actionType) end
    if b:GetAttribute("spell") ~= castId then b:SetAttribute("spell", castId) end
    if b:GetAttribute("unit") ~= unit then b:SetAttribute("unit", unit) end
    if b:GetAttribute("target-slot") ~= slot then b:SetAttribute("target-slot", slot) end
    if not b.mouseOn then
        b:EnableMouse(true)
        b.mouseOn = true
    end
    b.trackerId = trackerId
    live[trackerId] = entry
    if not recheckTicker then recheckTicker = C_Timer.NewTicker(RECHECK_SECONDS, Recheck) end
    results[trackerId] = slot and ("clickable (slot " .. slot .. ")") or "clickable"
end

--- The entry is losing its occupant or its container. Out of combat only;
-- the next Sync for the next occupant turns it back on.
function MissingCast.Release(entry)
    local b = entry and entry.castButton
    if b and not InCombatLockdown() then DisableButton(b) end
end

--- One line for /scoot debug sa missing <id>.
function MissingCast.DebugLine(trackerId, tracker, entry)
    local b = entry and entry.castButton
    local what
    if tracker and tracker.kind == "weaponbuff" then
        local slot = b and b:GetAttribute("target-slot")
        local ok, targeting = pcall(SpellCanTargetItem)
        what = string.format("target-slot=%s SpellCanTargetItem=%s",
            tostring(slot or "none"), ok and tostring(targeting) or "error")
    else
        local castId = MissingCast.CastSpellFor(trackerId, tracker)
        what = "cast=" .. (castId and tostring(castId) or "none")
    end
    return string.format("%s clickable=%s shown=%s reason=%s",
        what,
        tostring(b and b.mouseOn or false),
        tostring(b and b:IsShown() or false),
        tostring(results[trackerId] or "not synced"))
end
