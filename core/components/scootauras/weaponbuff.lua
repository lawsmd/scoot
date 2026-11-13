-- scootauras/weaponbuff.lua - Weapon Buff trackers: the plain read behind the
-- reminder that shows while a wielded weapon carries no temporary enchantment
--
-- A poison, a sharpening stone or a weapon oil is a temporary enchantment on
-- the item in a weapon slot. It is no unit aura: the buff bar draws it from
-- the inventory slot (BuffFrame.lua UpdateTemporaryEnchantmentBuffs: the
-- weapon's texture, a SetInventoryItem tooltip), and no AuraContainer filter
-- can match it. What reports it is
-- C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot): a table while the item
-- in the slot carries one, nothing otherwise. The return carries no secrecy
-- annotation on either client (PaperDollInfoDocumentation.lua, retail's copy
-- and Forever's), and Blizzard compares its fields in ordinary Lua, so the
-- verdict is a plain boolean, legal to branch on in combat, and the tracker
-- owns no container. missing.lua draws the reminder and asks this file for
-- the verdict (Missing.UpdateGate).
--
-- Any temporary enchantment counts as present. Nothing maps an enchant id to
-- a name or an icon, so the reminder shows the weapon's own icon, as the buff
-- bar does.
local addonName, addon = ...

local SAU = addon.ScootAuras

local WeaponBuff = {}
SAU.WeaponBuff = WeaponBuff

local MAIN_HAND = INVSLOT_MAINHAND or 16
local OFF_HAND = INVSLOT_OFFHAND or 17

-- The hands a tracker's unit names, main hand first.
local HANDS = {
    weapons = { MAIN_HAND, OFF_HAND },
    mainhand = { MAIN_HAND },
    offhand = { OFF_HAND },
}
local HAND_NAMES = { [MAIN_HAND] = "main hand", [OFF_HAND] = "off hand" }

local POLL_SECONDS = 1

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

--- The hands a unit token names. An unknown token watches both.
local function HandsFor(unit)
    return HANDS[unit] or HANDS.weapons
end

--------------------------------------------------------------------------------
-- The read
--------------------------------------------------------------------------------

--- The item in a slot when it is a weapon that can carry a temporary
-- enchantment, as itemID, classID, subClassID. Nil for an empty slot, and for
-- a shield or a held item, which sit in the off hand and take none. A fishing
-- pole is a weapon to the item tables and is left out as well. The second
-- return says why nothing came back: "none" or "unknown".
local function WieldedWeapon(slot)
    local ok, itemID = pcall(GetInventoryItemID, "player", slot)
    if not ok or IsSecret(itemID) then return nil, "unknown" end
    if type(itemID) ~= "number" then return nil, "none" end

    local getInstant = C_Item and C_Item.GetItemInfoInstant
    if type(getInstant) ~= "function" then return nil, "unknown" end
    local iok, _, _, _, _, _, classID, subClassID = pcall(getInstant, itemID)
    if not iok or IsSecret(classID) or IsSecret(subClassID) then return nil, "unknown" end
    if type(classID) ~= "number" then return nil, "unknown" end

    local weaponClass = Enum and Enum.ItemClass and Enum.ItemClass.Weapon
    if weaponClass == nil or classID ~= weaponClass then return nil, "none" end
    local pole = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole
    if pole ~= nil and subClassID == pole then return nil, "none" end
    return itemID, classID, subClassID
end

--- One slot's state, and the enchantment record when it has one:
--   "buffed"   a weapon carrying a temporary enchantment
--   "bare"     a weapon carrying none
--   "none"     nothing in the slot that could carry one
--   "unknown"  a read failed or came back secret
-- Only "bare" ever lights a reminder: an unreadable slot is never counted as
-- missing, the rule the roster scan follows for a unit it cannot read.
function WeaponBuff.SlotState(slot)
    local itemID, why = WieldedWeapon(slot)
    if not itemID then return why end

    local read = C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo
    if type(read) ~= "function" then return "unknown" end
    local ok, info = pcall(read, slot)
    if not ok or IsSecret(info) then return "unknown" end
    if info == nil then return "bare" end
    if type(info) ~= "table" then return "unknown" end
    return "buffed", info
end

--- Whether a watched hand holds a weapon with no temporary enchantment, and
-- the first such slot.
function WeaponBuff.Missing(tracker)
    for _, slot in ipairs(HandsFor(tracker and tracker.unit)) do
        if WeaponBuff.SlotState(slot) == "bare" then
            return true, slot
        end
    end
    return false, nil
end

-- A file id only: SAU.PaintTrackerIcon reads a string as an atlas name.
local function SlotTexture(slot)
    local ok, texture = pcall(GetInventoryItemTexture, "player", slot)
    if not ok or IsSecret(texture) or type(texture) ~= "number" then return nil end
    return texture
end

--- The icon of the weapon a tracker on this unit is about: the first bare
-- hand, so a reminder on "weapons" shows the weapon that needs the buff, else
-- the unit's first hand. Nil with nothing in that hand.
function WeaponBuff.Icon(unit)
    local hands = HandsFor(unit)
    for _, slot in ipairs(hands) do
        if WeaponBuff.SlotState(slot) == "bare" then
            local texture = SlotTexture(slot)
            if texture then return texture end
        end
    end
    return SlotTexture(hands[1])
end

--------------------------------------------------------------------------------
-- Upkeep: events are the fast path, the poll is the guarantee
--------------------------------------------------------------------------------

local ticker = nil
-- What each live tracker last painted: the verdict, the bare slot and the icon
-- in one string, so a pass with nothing moved costs the reads and no repaint.
local seen = {}

function WeaponBuff.AnyLive()
    for trackerId in pairs(SAU._activeStates) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and tracker.kind == "weaponbuff" then return true end
    end
    return false
end

--- Repaints every live Weapon Buff tracker whose verdict, bare slot or weapon
-- moved since the last pass. Missing.Restyle is Scoot-frame work throughout,
-- so this is legal in combat, where a poison can run out. WEAPON_ENCHANT_CHANGED,
-- WEAPON_SLOT_CHANGED and PLAYER_EQUIPMENT_CHANGED call it (events.lua), and so
-- does the poll below.
function WeaponBuff.Refresh()
    local Missing = SAU.Missing
    if not Missing then return end
    for trackerId, state in pairs(SAU._activeStates) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and tracker.kind == "weaponbuff" then
            local missing, slot = WeaponBuff.Missing(tracker)
            local signature = (missing and "bare" or "ok") .. ":" .. tostring(slot)
                .. ":" .. tostring(WeaponBuff.Icon(tracker.unit))
            if seen[trackerId] ~= signature then
                seen[trackerId] = signature
                Missing.Restyle(trackerId, tracker, state)
            end
        end
    end
end

--- Starts or stops the poll to match the live Weapon Buff trackers. The two
-- weapon events cover an enchantment applied, cancelled or swapped away with
-- its weapon; the poll covers one that timed out without either arriving.
function WeaponBuff.SyncTicker()
    if WeaponBuff.AnyLive() then
        if not ticker then
            ticker = C_Timer.NewTicker(POLL_SECONDS, function()
                if WeaponBuff.AnyLive() then
                    WeaponBuff.Refresh()
                else
                    WeaponBuff.SyncTicker()
                end
            end)
        end
    elseif ticker then
        ticker:Cancel()
        ticker = nil
        wipe(seen)
    end
end

--------------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------------

local function Describe(v)
    if IsSecret(v) then return "secret" end
    return tostring(v)
end

-- A client that splits weapon enchantments by type (permanent, temporary,
-- imbue) lists them per weapon slot through C_Item.GetWeaponEnchantInfo. The
-- tracker does not read it; the rows are here so one look says which type a
-- given buff is.
local WEAPON_SLOT_KEYS = { [MAIN_HAND] = "MainHand", [OFF_HAND] = "OffHand" }

local function AddTypedRows(add, slot)
    local read = C_Item and C_Item.GetWeaponEnchantInfo
    local key = Enum and Enum.WeaponSlot and Enum.WeaponSlot[WEAPON_SLOT_KEYS[slot]]
    if type(read) ~= "function" or key == nil then return end
    local ok, rows = pcall(read, key)
    if not ok then
        add("    C_Item.GetWeaponEnchantInfo: error %s", tostring(rows))
        return
    end
    if IsSecret(rows) or type(rows) ~= "table" then
        add("    C_Item.GetWeaponEnchantInfo: %s", Describe(rows))
        return
    end
    local count = 0
    for index, row in pairs(rows) do
        count = count + 1
        if IsSecret(row) or type(row) ~= "table" then
            add("    [%s] %s", tostring(index), Describe(row))
        else
            add("    [%s] has=%s type=%s timeLeft=%s charges=%s enchantID=%s icon=%s",
                tostring(index), Describe(row.hasEnchant), Describe(row.enchantType),
                Describe(row.timeLeft), Describe(row.charges), Describe(row.enchantID),
                Describe(row.enchantIconID))
        end
    end
    if count == 0 then add("    C_Item.GetWeaponEnchantInfo: (empty)") end
end

--- The weapon read, for /scoot debug sa missing <id>: which call answers, each
-- watched hand's item and state with the raw record, and the verdict. Every
-- line is a fresh read.
function WeaponBuff.AddDebug(add, tracker)
    add("")
    add("--- weapon buff ---")
    add("read=%s typedRead=%s poll=%s",
        (C_PaperDollInfo and type(C_PaperDollInfo.GetTemporaryEnchantmentInfo) == "function")
            and "C_PaperDollInfo.GetTemporaryEnchantmentInfo" or "none (every slot reads unknown)",
        tostring(C_Item ~= nil and type(C_Item.GetWeaponEnchantInfo) == "function"),
        tostring(ticker ~= nil))
    for _, slot in ipairs(HandsFor(tracker.unit)) do
        local itemID, classID, subClassID = WieldedWeapon(slot)
        local state, info = WeaponBuff.SlotState(slot)
        if itemID then
            add("  %s (slot %d): item=%d class=%s subclass=%s state=%s", HAND_NAMES[slot] or "?", slot,
                itemID, tostring(classID), tostring(subClassID), state)
        else
            local ok, rawID = pcall(GetInventoryItemID, "player", slot)
            add("  %s (slot %d): item=%s state=%s (%s)", HAND_NAMES[slot] or "?", slot,
                ok and Describe(rawID) or "error", state,
                state == "none" and "empty, or not a weapon that takes a buff" or "read failed")
        end
        if info then
            add("    enchantID=%s remainingMs=%s charges=%s hasExpiration=%s",
                Describe(info.enchantID), Describe(info.remainingTimeMs),
                Describe(info.chargesRemaining), Describe(info.hasExpirationTime))
        end
        AddTypedRows(add, slot)
    end
    local missing, slot = WeaponBuff.Missing(tracker)
    add("verdict: missing=%s%s icon=%s", tostring(missing),
        slot and (" (" .. (HAND_NAMES[slot] or tostring(slot)) .. ")") or "",
        tostring(WeaponBuff.Icon(tracker.unit)))
end
