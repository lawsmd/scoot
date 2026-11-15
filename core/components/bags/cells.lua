--------------------------------------------------------------------------------
-- core/components/bags/cells.lua
-- The item cells. Each is Blizzard's ContainerFrameItemButtonTemplate on a
-- holder whose ID is the bag, so every click, drag, tooltip and modified click
-- is Blizzard's own code. This file draws the slot behind the cell and paints
-- the item the way ContainerFrameMixin:UpdateItems does.
--
-- The template's Initialize is not called: it asks its parent whether it is a
-- combined container, which the holder is not. The three writes it makes that
-- matter (the bag id through the "bagid" attribute, the slot id, Show) are
-- made here. Nothing here writes a field Blizzard's click path reads: that
-- path reads the bag id, the slot id and the cursor, all set through C.
--
-- The slot art is the template's own: the empty slot atlas the button draws
-- into its icon when the slot is empty, and its normal texture.
--------------------------------------------------------------------------------

local _, addon = ...

local Bags = addon.Bags

local Cells = {}
Bags.Cells = Cells

local pools = {}     -- bag id -> indexed pool of cells
local holders = {}   -- bag id -> holder frame
local counts = {}    -- bag id -> slots drawn

--------------------------------------------------------------------------------
-- Cells
--------------------------------------------------------------------------------

local function BagKey(bag)
    return bag < 0 and ("N" .. -bag) or tostring(bag)
end

-- The keyring's cells live in the keyring window, the rest in the bag window.
local function HolderParent(bag)
    if Bags.IsKeyring(bag) and Bags.Keyring then return Bags.Keyring.Content() end
    return Bags.Window.Content()
end

local function Holder(bag)
    local holder = holders[bag]
    if holder then return holder end
    holder = CreateFrame("Frame", nil, HolderParent(bag))
    holder:SetAllPoints()
    holder:SetID(bag)
    holders[bag] = holder
    return holder
end

local function CreateCell(slot, bag)
    local name = addon.Brand .. "BagItem" .. BagKey(bag) .. "_" .. slot
    local cell = CreateFrame("ItemButton", name, Holder(bag), "ContainerFrameItemButtonTemplate")
    cell:SetSize(Bags.CELL, Bags.CELL)
    cell:SetBagID(bag)
    cell:SetID(slot)
    cell:HookScript("OnEnter", function(self)
        if Bags.Delete then Bags.Delete.Attach(self) end
    end)
    cell:HookScript("OnLeave", function()
        if Bags.Delete then Bags.Delete.MaybeHide() end
    end)
    return cell
end

local function Pool(bag)
    local pool = pools[bag]
    if not pool then
        pool = addon.Pool.NewIndexed(CreateCell)
        pools[bag] = pool
    end
    return pool
end

--- The cell for a bag's slot, created on first use.
function Cells.Get(bag, slot)
    return Pool(bag):Get(slot, bag)
end

--- The frame a bag's cells are on, or nil before the bag is drawn.
function Cells.Holder(bag)
    return holders[bag]
end

--- The cell drawn for a slot, or nil.
function Cells.Find(bag, slot)
    local pool = pools[bag]
    local n = counts[bag] or 0
    if not pool or slot > n then return nil end
    return pool.items[slot]
end

--- Keep the first n cells of a bag; hide the rest.
function Cells.SetCount(bag, n)
    counts[bag] = n
    Pool(bag):HideFrom(n + 1)
end

--- Hide every bag the window no longer draws.
function Cells.HideOthers(drawn)
    for bag, pool in pairs(pools) do
        if not drawn[bag] then
            counts[bag] = 0
            pool:HideFrom(1)
        end
    end
end

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------

local function Paint(cell, bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local texture = info and info.iconFileID
    local quality = info and info.quality
    local link = info and info.hyperlink

    cell:SetBagID(bag)
    cell:SetID(slot)
    if ClearItemButtonOverlay then ClearItemButtonOverlay(cell) end
    if cell.SetHasItem then cell:SetHasItem(texture) end
    if cell.SetItemButtonTexture then
        cell:SetItemButtonTexture(texture)
    else
        SetItemButtonTexture(cell, texture)
    end
    -- The Forever client draws the empty slot here; a client without the
    -- method draws it in SetItemButtonTexture.
    if cell.SyncAppearanceWithHasItem then cell:SyncAppearanceWithHasItem() end
    SetItemButtonQuality(cell, quality, link, false, info and info.isBound)
    SetItemButtonCount(cell, info and info.stackCount or 0)
    SetItemButtonDesaturated(cell, info and info.isLocked or false)

    local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
    if cell.UpdateQuestItem then
        cell:UpdateQuestItem(quest and quest.isQuestItem, quest and quest.questID, quest and quest.isActive)
    end
    if cell.UpdateNewItem then cell:UpdateNewItem(quality) end
    if cell.UpdateJunkItem then cell:UpdateJunkItem(quality, info and info.hasNoValue) end
    if cell.SetReadable then cell:SetReadable(info and info.isReadable) end
    if cell.UpdateCooldown then cell:UpdateCooldown(texture) end
    if cell.UpdateItemContextMatching then cell:UpdateItemContextMatching() end
    if cell.SetMatchesSearch then cell:SetMatchesSearch(not (info and info.isFiltered)) end
    cell:Show()
end

function Cells.PaintSlot(bag, slot)
    local cell = Cells.Find(bag, slot)
    if cell then Paint(cell, bag, slot) end
end

function Cells.PaintAll()
    for bag, n in pairs(counts) do
        for slot = 1, n do
            local cell = pools[bag].items[slot]
            if cell then Paint(cell, bag, slot) end
        end
    end
end

function Cells.PaintCooldowns()
    for bag, n in pairs(counts) do
        for slot = 1, n do
            local cell = pools[bag].items[slot]
            if cell and cell.UpdateCooldown then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                cell:UpdateCooldown(info and info.iconFileID)
            end
        end
    end
end

function Cells.PaintSearch()
    for bag, n in pairs(counts) do
        for slot = 1, n do
            local cell = pools[bag].items[slot]
            if cell and cell.SetMatchesSearch then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                cell:SetMatchesSearch(not (info and info.isFiltered))
            end
        end
    end
end

--- Every drawn cell, for the Pick Lock scan: fn(cell, bag, slot).
function Cells.Each(fn)
    for bag, n in pairs(counts) do
        for slot = 1, n do
            local cell = pools[bag].items[slot]
            if cell then fn(cell, bag, slot) end
        end
    end
end
