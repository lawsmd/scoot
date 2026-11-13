--------------------------------------------------------------------------------
-- core/components/bags/picklock.lua
-- Pick Lock on a right-click. For a player who knows the spell, each locked
-- lockbox in the window gets a secure button over its cell: a right-click
-- casts Pick Lock with the box as the spell's item target, through the
-- SecureActionButton's target-bag and target-slot attributes. A left-click
-- passes through to the cell, so the box still picks up and drags.
--
-- The overlays sit on a holder parented to UIParent, never in the window: a
-- secure child would make the window protected, and the window has to open
-- and close in combat. A protected frame can only be placed, shown or hidden
-- out of combat, so the overlays are placed out of combat and the holder is
-- hidden as combat starts, before the lockdown. In combat a right-click on a
-- lockbox reaches Blizzard's cell and the game says the box is locked.
--
-- No API reports a locked box. The test is the LOCKED line in the item's
-- tooltip data, read only for Miscellaneous items.
--------------------------------------------------------------------------------

local _, addon = ...

local Bags = addon.Bags

local PickLock = {}
Bags.PickLock = PickLock

local SPELL_ID = 1804
local MISC_CLASS = (Enum.ItemClass and Enum.ItemClass.Miscellaneous) or 15

local holder
local pool
local active = {}

local function Known()
    return IsPlayerSpell and IsPlayerSpell(SPELL_ID) or false
end

local function IsLockedBox(bag, slot, info)
    if not info or not info.itemID then return false end
    local classID = select(6, C_Item.GetItemInfoInstant(info.itemID))
    if classID ~= MISC_CLASS then return false end
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return false end
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    local lines = data and data.lines
    if not lines then return false end
    for _, line in ipairs(lines) do
        if line.leftText == LOCKED then return true end
    end
    return false
end

local function CreateOverlay()
    local b = CreateFrame("Button", nil, holder, "SecureActionButtonTemplate")
    b:RegisterForClicks("RightButtonUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type2", "spell")
    b:SetAttribute("spell2", SPELL_ID)
    -- pcall: on a client that restricts the call, the overlay keeps the left
    -- click and the box cannot be picked up while it is locked.
    pcall(b.SetPassThroughButtons, b, "LeftButton")
    b:SetScript("OnEnter", function(self)
        local cell = self.cell
        if not cell then return end
        local onEnter = cell:GetScript("OnEnter")
        if onEnter then onEnter(cell) end
        if Bags.Delete then Bags.Delete.Attach(cell) end
    end)
    b:SetScript("OnLeave", function(self)
        local cell = self.cell
        if cell then
            local onLeave = cell:GetScript("OnLeave")
            if onLeave then onLeave(cell) end
        end
        if Bags.Delete then Bags.Delete.MaybeHide() end
    end)
    return b
end

local function ResetOverlay(b)
    b.cell = nil
    b:ClearAllPoints()
    b:Hide()
end

local function EnsureHolder()
    if holder then return end
    holder = CreateFrame("Frame", addon.Brand .. "BagPickLock", UIParent)
    holder:SetAllPoints(UIParent)
    holder:SetFrameStrata("MEDIUM")
    holder:Hide()
    pool = addon.Pool.New(CreateOverlay, ResetOverlay)
end

local function ReleaseAll()
    for i = #active, 1, -1 do
        pool:Release(active[i])
        active[i] = nil
    end
end

--- Out of combat only: one overlay per locked box, the holder shown with the
--- window.
local function Place()
    if InCombatLockdown() then return end
    EnsureHolder()
    ReleaseAll()
    local window = Bags.Window.Frame()
    if not (window and window:IsShown() and Known()) then
        holder:Hide()
        return
    end
    Bags.Cells.Each(function(cell, bag, slot)
        if Bags.IsKeyring(bag) then return end
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if IsLockedBox(bag, slot, info) then
            local b = pool:Acquire()
            b.cell = cell
            b:SetAttribute("target-bag", bag)
            b:SetAttribute("target-slot", slot)
            b:SetAllPoints(cell)
            b:SetFrameLevel(cell:GetFrameLevel() + 2)
            b:Show()
            active[#active + 1] = b
        end
    end)
    holder:SetShown(#active > 0)
end

function PickLock.Queue()
    if not Bags.component then return end
    Bags.component:RunOutOfCombat(Place, "pickLock")
end

--- The window closed. In combat the holder is already hidden.
function PickLock.HideAll()
    if not holder or InCombatLockdown() then return end
    ReleaseAll()
    holder:Hide()
end

-- PLAYER_REGEN_DISABLED fires before the lockdown starts, the last moment a
-- protected frame can be hidden. The overlays are released too: an overlay
-- anchored to a cell, even hidden, bars the cell from moving in combat, and a
-- loot refresh in combat places the cells again.
addon.Events.On("Bags.pickLock", "PLAYER_REGEN_DISABLED", function()
    if not holder then return end
    ReleaseAll()
    holder:Hide()
end)
addon.Events.On("Bags.pickLock", "PLAYER_REGEN_ENABLED", function()
    if Bags.active then PickLock.Queue() end
end)
addon.Events.On("Bags.pickLock", "SPELLS_CHANGED", function()
    if Bags.active then PickLock.Queue() end
end)
