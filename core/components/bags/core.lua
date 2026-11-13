--------------------------------------------------------------------------------
-- core/components/bags/core.lua
-- The bag window: one window of every held bag and the reagent bag, each bag
-- on lines of its own behind a cell that shows the bag's icon, in Blizzard's
-- art. Where the client has a keyring, the keyring opens in a small window of
-- its own from a button in the bag window (keyring.lua). Both TOCs list these
-- files.
--
-- Blizzard's container frames stay the record of what is open. They are
-- parked under a hidden parent, so Blizzard's own functions open and close
-- them as before (the keybinds, the bag bar, a merchant, Escape through
-- CloseAllWindows), and the window follows: a post-hook on each of those
-- functions reads IsAnyBagOpen, which reads the frames' own shown flags. The
-- frames' OnShow and OnHide never run while parked, so the ContainerFrame.*
-- callbacks they fire cannot be the signal.
--
-- An item cell is Blizzard's ContainerFrameItemButtonTemplate. Its OnClick
-- (use, sell, bank, split, modified clicks, drag) is Blizzard's code and reads
-- the bag from the "bagid" attribute, so a hardware click on a cell runs
-- untainted and uses an item in combat. Nothing in the window is protected,
-- so it shows, hides and lays out in combat. The one secure piece, Pick Lock,
-- sits on a holder of its own (picklock.lua).
--------------------------------------------------------------------------------

local _, addon = ...

local Bags = {}
addon.Bags = Bags

Bags.COMPONENT_ID = "bags"
Bags.CATEGORY = "bags"
Bags.OWNER = "Bags"

-- Blizzard's combined window: 37 wide cells, 5 apart.
Bags.CELL = 37
Bags.GAP = 5

local NUM_BAG_SLOTS = (Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots) or 4
local NUM_REAGENT_SLOTS = (Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumReagentBagSlots) or 0

local BACKPACK = (Enum.BagIndex and Enum.BagIndex.Backpack) or 0
local KEYRING = KEYRING_CONTAINER or (Enum.BagIndex and Enum.BagIndex.Keyring)
Bags.KEYRING = KEYRING

-- Blizzard's container frames, with the keyring's where the client has one.
-- Past the last one, the global is nil.
local MAX_CONTAINER_FRAMES = 13

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function Bags.Get(key)
    local comp = Bags.component
    local db = comp and comp.db
    local value = db and db[key]
    if value == nil and comp and comp.settings[key] then
        value = comp.settings[key].default
    end
    return value
end

--------------------------------------------------------------------------------
-- The bags the window draws
--------------------------------------------------------------------------------

function Bags.HasKeyring()
    if not KEYRING then return false end
    if C_ActionBar and C_ActionBar.ShouldShowKeyring then
        return C_ActionBar.ShouldShowKeyring() and true or false
    end
    return false
end

--- The keyring's slot count, the way Blizzard's keyring frame reads it.
function Bags.KeyringSize()
    if not Bags.HasKeyring() then return 0 end
    local n = GetKeyRingSize and GetKeyRingSize() or C_Container.GetContainerNumSlots(KEYRING)
    return tonumber(n) or 0
end

--- The bag ids in line order: the backpack, the held bags, the reagent bag.
--- A bag with no slots is left out. The keyring has its own window.
function Bags.BagList()
    local list = {}
    local function add(bag)
        local n = C_Container.GetContainerNumSlots(bag)
        if n and n > 0 then list[#list + 1] = bag end
    end
    add(BACKPACK)
    for bag = 1, NUM_BAG_SLOTS do add(bag) end
    for i = 1, NUM_REAGENT_SLOTS do add(NUM_BAG_SLOTS + i) end
    return list
end

function Bags.IsBackpack(bag)
    return bag == BACKPACK
end

function Bags.IsKeyring(bag)
    return KEYRING ~= nil and bag == KEYRING
end

--------------------------------------------------------------------------------
-- Blizzard's container frames
--------------------------------------------------------------------------------

local function ContainerFrames()
    local list = {}
    if ContainerFrameCombinedBags then list[#list + 1] = ContainerFrameCombinedBags end
    for i = 1, MAX_CONTAINER_FRAMES do
        local f = _G["ContainerFrame" .. i]
        if not f then break end
        list[#list + 1] = f
    end
    return list
end

local function GamepadActive()
    return addon.Gamepad and addon.Gamepad.IsActive and addon.Gamepad.IsActive() or false
end

-- Parked once, at the world pass, while every bag is closed: parking a shown
-- frame would run its OnHide inside this addon's execution.
local function Park()
    if Bags.parked or not addon.NativeFrame then return end
    for _, f in ipairs(ContainerFrames()) do
        addon.NativeFrame:Suppress(f, Bags.OWNER, "park")
    end
    Bags.parked = true
end

--------------------------------------------------------------------------------
-- Open state
--------------------------------------------------------------------------------

-- The bag window's state: any held bag or the reagent bag open in Blizzard's
-- frames. IsBagOpen reads the parked frames' own shown flags.
local function BagsOpen()
    if not IsBagOpen then return IsAnyBagOpen and IsAnyBagOpen() or false end
    for bag = BACKPACK, NUM_BAG_SLOTS + NUM_REAGENT_SLOTS do
        if IsBagOpen(bag) then return true end
    end
    return false
end

function Bags.KeyringOpen()
    return Bags.HasKeyring() and IsBagOpen and IsBagOpen(KEYRING) and true or false
end

local function StandardOpen()
    if IsAnyStandardHeldBagOpen then return IsAnyStandardHeldBagOpen() end
    return BagsOpen()
end

local syncQueued = false
local wasStandard = false

-- Blizzard opens the reagent bag and the keyring in frames of their own, so B
-- after Shift+B or a merchant closes the backpack and leaves those open. The
-- windows close as one: when the held bags close under the bag window and
-- another bag is still open, the rest close too.
local function Sync()
    syncQueued = false
    if not Bags.active then return end
    local standard = StandardOpen()
    local shown = Bags.Window.IsBuilt() and Bags.Window.Frame():IsShown()
    if shown and wasStandard and not standard and (BagsOpen() or Bags.KeyringOpen()) then
        wasStandard = false
        Bags.CloseAll()
        return
    end
    wasStandard = standard
    -- The keyring window opens from its own button only, and closes with the
    -- bag window (window.lua).
    if BagsOpen() then
        Bags.Window.Open()
    else
        Bags.Window.Close()
    end
end

--- Coalesce the open state to one read after Blizzard's call has finished.
function Bags.QueueSync()
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(0, Sync)
end

local OPEN_PATHS = {
    "OpenBag", "CloseBag", "ToggleBag",
    "OpenBackpack", "CloseBackpack", "ToggleBackpack",
    "OpenAllBags", "CloseAllBags", "ToggleAllBags",
    "ContainerFrame_GenerateFrame",
}

local function InstallOpenPaths()
    if Bags.hooked then return end
    Bags.hooked = true
    for _, name in ipairs(OPEN_PATHS) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, Bags.QueueSync)
        end
    end
end

--- The window's close button and the end of a session: close Blizzard's
--- bags, which the hooks above follow.
function Bags.CloseAll()
    if CloseAllBags then CloseAllBags() end
    Bags.QueueSync()
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Lay the window out again and repaint every cell. Runs in combat too:
--- nothing in the window is protected.
function Bags.Refresh()
    if not Bags.active then return end
    local bags = Bags.Window.IsBuilt()
    local keyring = Bags.Keyring and Bags.Keyring.IsShown()
    if not (bags or keyring) then return end
    if bags then Bags.Layout.Run() end
    if keyring then Bags.Layout.RunKeyring() end
    Bags.Cells.PaintAll()
    if bags then Bags.Window.UpdateFooter() end
    if Bags.PickLock then Bags.PickLock.Queue() end
end

local refreshQueued = false

function Bags.QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        Bags.Refresh()
    end)
end

--- Apply the page's settings: scale, the header and footer pieces, the lines.
function Bags.ApplySettings()
    Bags.Window.ApplySettings()
    if Bags.Keyring then Bags.Keyring.ApplySettings() end
    if Bags.Delete and Bags.Get("showDelete") == false then Bags.Delete.Hide() end
    Bags.Refresh()
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

local function Start(comp)
    if Bags.active then return end
    if GamepadActive() then return end
    Bags.active = true
    Park()
    InstallOpenPaths()

    comp:On("BAG_UPDATE_DELAYED", function() Bags.QueueRefresh() end)
    comp:On("BAG_CONTAINER_UPDATE", function() Bags.QueueRefresh() end)
    comp:On("PLAYER_EQUIPMENT_CHANGED", function() Bags.QueueRefresh() end)
    comp:On("ITEM_LOCK_CHANGED", function(_, _, bag, slot)
        if slot then Bags.Cells.PaintSlot(bag, slot) end
    end)
    comp:On("BAG_UPDATE_COOLDOWN", function() Bags.Cells.PaintCooldowns() end)
    comp:On("INVENTORY_SEARCH_UPDATE", function() Bags.Cells.PaintSearch() end)
    comp:On("BAG_NEW_ITEMS_UPDATED", function() Bags.Cells.PaintAll() end)
    comp:On("PLAYER_MONEY", function() Bags.Window.UpdateFooter() end)
    comp:On("MERCHANT_SHOW", function() Bags.Cells.PaintAll() end)
    comp:On("MERCHANT_CLOSED", function() Bags.Cells.PaintAll() end)

    Bags.QueueSync()
end

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype
    local comp = Component:New({
        id = Bags.COMPONENT_ID,
        name = "Bags",
        settings = {
            columns = { type = "addon", default = 8 },
            scale = { type = "addon", default = 90 },
            showFreeSlots = { type = "addon", default = true },
            showSortButton = { type = "addon", default = true },
            showDelete = { type = "addon", default = true },
        },
        ApplyStyling = function()
            Bags.ApplySettings()
        end,
    })
    self:RegisterComponent(comp)
    Bags.component = comp

    -- The Features switch is the opt-in; the window starts whether or not a
    -- setting has been changed from its default.
    addon.Events.OnWorldEntered(function()
        Start(comp)
    end)
end, Bags.CATEGORY)
