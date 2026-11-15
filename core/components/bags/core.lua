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
    -- Adopted: the window is a child of Blizzard's combined frame and shows
    -- and hides with it.
    if Bags.adopted then
        if BagsOpen() then
            if Bags.HideNative then Bags.HideNative() end
            Bags.Refresh()
        end
        return
    end
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
    if bags and Bags.adopted and Bags.QueueNav then Bags.QueueNav() end
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

local function Listen(comp)
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
end

local function Start(comp)
    if Bags.active then return end
    -- Under the gamepad UI Blizzard's frames are not parked: the window rides
    -- on Blizzard's combined frame (the sections below).
    if GamepadActive() then
        Bags.StartGamepad(comp)
        return
    end
    Bags.active = true
    Park()
    InstallOpenPaths()
    Listen(comp)
    Bags.QueueSync()
end

--------------------------------------------------------------------------------
-- Under the gamepad UI
--------------------------------------------------------------------------------

-- The window becomes a child of Blizzard's combined bag frame, so it shows
-- and hides with it, and the controller is tied to it as the next section
-- describes. Bags.adopted marks the session.

--------------------------------------------------------------------------------
-- The controller's buttons
--------------------------------------------------------------------------------

-- The controller lands on Blizzard's own item buttons, not on this window's
-- cells. Blizzard's bag prompts (Select, Use, Equip, Sell, Open, Read, More
-- Actions) read hasItem, the bag and the slot off the button the controller
-- is on. On a cell of this window those are this addon's writes: the prompts
-- then build their binding set as the addon, and the next walk of the binding
-- stack ends in the protected SetPreferredGamepadInteractTarget. On Blizzard's
-- button they are Blizzard's, and every prompt and its action is Blizzard's
-- code on Blizzard's button, in combat too.
--
-- So Blizzard's combined frame stays shown, drawn at nothing, with this
-- window over it. Two of Blizzard's own setters, which store through its
-- secure helper and accept an addon's call out of combat, tie the two
-- together: SmartNavigation_SetCustomCursorAnchorPointForFrame puts the
-- cursor for each of Blizzard's buttons on this window's cell for the same
-- bag and slot, and SmartNavigation_AddJumpNavigationOverride gives each its
-- four targets. Blizzard's bag bar buttons are tied to the bag icons the same
-- way.
--
-- Navigation is a grid over the window as drawn, the bag icons in its first
-- column: left and right walk a row and wrap at its ends, up and down move
-- one row to the nearest cell in the same column, up from the top row goes
-- to the portrait or the sort button, whichever is over that half, and down
-- from the bottom row stays. The header carries Blizzard's portrait button
-- over this window's portrait and its search box over this window's; the keyring button is not reachable.
-- Everything in this window but the sort button is marked ignored, so
-- Blizzard's navigation never lands on a cell.

local DIM_ALPHA = 0.55
local BAND_ALPHA = 0.07
local LOG_KEEP = 10

local navHolder
local navBand
local navGlow
local navIgnored = setmetatable({}, { __mode = "k" })
local navAnchored = setmetatable({}, { __mode = "k" })
local navCurrent          -- the item button the controller or the pointer is on
local navCell             -- this window's cell for it
local navLog = {}
local navStats = { matched = 0, missing = 0, builds = 0 }

local function StackTaint()
    local shared = _G.GamepadSharedUtility
    local manager = shared and shared.InputBindingManager
    local stack = manager and manager.bindingSetStack
    if not stack then return nil end
    for i, set in ipairs(stack) do
        local ok, by = _G.issecurevariable(stack, i)
        if not ok then return ("%s (slot, %s)"):format(tostring(set.name), tostring(by)) end
        ok, by = _G.issecurevariable(set, "treatBindsAsCore")
        if not ok then return ("%s (%s)"):format(tostring(set.name), tostring(by)) end
    end
    return nil
end

-- Keep the last few things the controller did here, and the first moment the
-- binding stack held a set that is not Blizzard's.
local function Note(what)
    navLog[#navLog + 1] = ("%.1f %s"):format(GetTime(), what)
    if #navLog > LOG_KEEP then table.remove(navLog, 1) end
    if Bags.navTaint then return end
    local function check(when)
        if Bags.navTaint then return end
        local found = StackTaint()
        if not found then return end
        Bags.navTaint = { set = found, when = when, log = { unpack(navLog) } }
    end
    check("during: " .. what)
    C_Timer.After(0, function() check("after: " .. what) end)
end

-- The press recorder: each face button's down edge while the window shows,
-- with what the engine bound to it at that moment, the top binding set, the
-- button the cursor is on and that slot's count, read again a moment later
-- so the log says whether the press used the item.
local FACE_KEYS = { "PAD1", "PAD2", "PAD3", "PAD4" }
local keyDown = {}

local function BindingManager()
    local shared = _G.GamepadSharedUtility
    return shared and shared.InputBindingManager
end

local function TopSetName()
    local manager = BindingManager()
    local stack = manager and manager.bindingSetStack
    local top = stack and stack[#stack]
    return top and tostring(top.name) or "core"
end

local function CursorSlot()
    local nav = _G.SmartNavigation
    local button = nav and nav.currentButton
    if not button then return nil, nil, "nothing" end
    local bag = button.bagID
    if type(bag) == "number" then
        local slot = button:GetID()
        return bag, slot, ("bag %d slot %d"):format(bag, slot)
    end
    return nil, nil, (button.GetName and button:GetName()) or "an unnamed button"
end

-- Whether SmartNavigation's currentButton was last written by Blizzard or
-- while its execution ran as an addon. Read at the press, since anything that
-- moves the cursor (opening chat) rewrites it.
local function CursorTaint()
    local nav = _G.SmartNavigation
    if not nav then return "no SmartNavigation" end
    local ok, by = _G.issecurevariable(nav, "currentButton")
    return ok and "written secure" or ("written tainted by " .. tostring(by))
end

local function SlotCount(bag, slot)
    if not bag then return "-" end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and tostring(info.stackCount) or "empty"
end

local function RecordPresses()
    for _, key in ipairs(FACE_KEYS) do
        local down = _G.IsKeyDown(key) and true or false
        if down ~= (keyDown[key] or false) then
            keyDown[key] = down
            if down then
                local bag, slot, on = CursorSlot()
                local before = SlotCount(bag, slot)
                local what = ("%s down -> %s, top set %s, cursor on %s (%s), count %s"):format(key,
                    tostring(_G.GetBindingAction(key, true) or ""), TopSetName(), on, CursorTaint(), before)
                C_Timer.After(0.3, function()
                    Note(("%s, then %s"):format(what, SlotCount(bag, slot)))
                end)
            end
        end
    end
end

local function ShowBag(bag)
    local lines = Bags.Layout.Lines()
    local step = Bags.CELL + Bags.GAP
    local found
    for _, line in ipairs(lines) do
        local alpha = (bag == nil or line.bag == bag) and 1 or DIM_ALPHA
        local holder = Bags.Cells.Holder(line.bag)
        if holder then holder:SetAlpha(alpha) end
        if line.icon then line.icon:SetAlpha(alpha) end
        if line.bag == bag then found = line end
    end
    if not navBand then return end
    if not found then
        navBand:Hide()
        return
    end
    local content = Bags.Window.Content()
    navBand:ClearAllPoints()
    navBand:SetPoint("TOPLEFT", content, "TOPLEFT", -2, -found.row * step + 2)
    navBand:SetPoint("RIGHT", content, "RIGHT", 2, 0)
    navBand:SetHeight(found.rows * step - Bags.GAP + 4)
    navBand:Show()
end

-- Blizzard's item buttons announce the one entered and the one left, for the
-- controller and the pointer alike, and this window's cells are the same
-- template, so both arrive here. The registry runs each listener apart from
-- the next, so nothing read here reaches Blizzard's own listeners.
local function ItemEntered(_, button)
    if not (Bags.adopted and button) then return end
    local bag, slot = button.bagID, button:GetID()
    if type(bag) ~= "number" then return end
    local cell = Bags.Cells.Find(bag, slot)
    if not cell then return end
    navCurrent, navCell = button, cell
    ShowBag(bag)
    if not navGlow then return end
    if cell == button then
        -- The pointer, on a cell of this window: the cell lights itself.
        navGlow:Hide()
        return
    end
    Note(("on bag %d slot %d"):format(bag, slot))
    -- Blizzard has just put the tooltip on its own button, which is somewhere
    -- under this window, and the tooltip asks its owner to place it again
    -- five times a second. The cell is the same template: it takes the
    -- tooltip over, and from then on the tooltip asks the cell.
    if cell.UpdateTooltip then cell:UpdateTooltip() end
    navGlow:ClearAllPoints()
    navGlow:SetAllPoints(cell)
    navGlow:Show()
end

local function ItemExited(_, button)
    if navCurrent ~= button then return end
    navCurrent, navCell = nil, nil
    if navGlow then navGlow:Hide() end
    -- A move to another slot enters it in the same pass; only a real leave
    -- brings the bags back to full.
    C_Timer.After(0, function()
        if not navCurrent then ShowBag(nil) end
    end)
end

local function BagEntered(_, bagButton)
    if not (Bags.adopted and bagButton and bagButton.GetBagID) then return end
    local bag = bagButton:GetBagID()
    if type(bag) == "number" then ShowBag(bag) end
end

local function BagLeft()
    C_Timer.After(0, function()
        if not navCurrent then ShowBag(nil) end
    end)
end

-- The loot recorder: an item opened from the bags shows Blizzard's loot
-- window, which takes the controller, and its hide should hand the controller
-- back to the bags (FrameHidden focuses the first shown frame unless the loot
-- window asked to return to player control). What the controls manager holds
-- at that moment, and a moment later, goes in the log.
local function FrameName(frame)
    if not frame then return "none" end
    if frame == _G.ContainerFrameCombinedBags then return "the bags" end
    return (frame.GetName and frame:GetName()) or "unnamed"
end

local function FocusState()
    local mode = _G.GamepadMode
    local fcm = mode and mode.FrameControlsManager
    if not fcm then return "no controls manager" end
    local shown = {}
    for _, f in ipairs(fcm.shownFrames or {}) do shown[#shown + 1] = FrameName(f) end
    local loot = _G.LootFrame
    return ("UI focused %s, focused %s, shown [%s], loot returns to player %s, suspended %s"):format(
        tostring(fcm.isUIFocused), FrameName(fcm.focusedFrame), table.concat(shown, ", "),
        tostring(loot and loot.returnToPlayerControl), FrameName(fcm.topSuspendedFrame))
end

local function LootOpened(_, _, isAutoLoot, acquiredFromItem)
    if not Bags.adopted then return end
    Note(("loot opened: auto %s, from an item %s; %s"):format(
        tostring(isAutoLoot), tostring(acquiredFromItem), FocusState()))
end

local function LootHidden()
    if not Bags.adopted then return end
    Note("loot hidden: " .. FocusState())
    C_Timer.After(0.2, function() Note("loot hidden +0.2s: " .. FocusState()) end)
end

-- Blizzard writes some of these itself on every open, so the stored value is
-- compared, not a copy kept here.
local function SetTarget(button, direction, target)
    if button["smartNavigationOverride-" .. direction.dirKey] == target then return end
    _G.SmartNavigation_AddJumpNavigationOverride(button, direction, target)
end

local function SetCursor(button, region)
    navAnchored[button] = true
    if button["smartNavigationCustomCursorAnchor-relativeTo"] == region then return end
    local nav = _G.SmartNavigation
    local anchor = _G.CreateAnchor("RIGHT", region, "LEFT",
        nav and nav.cursorOffsetX or 0, nav and nav.cursorOffsetY or 0)
    _G.SmartNavigation_SetCustomCursorAnchorPointForFrame(button, anchor)
end

-- Blizzard places its cursor once, when it selects a button
-- (SmartNavigation UpdateCursorPosition, from SelectButton). On the first open
-- it selects its top-left button before this window has given that button
-- its place here, so the cursor is drawn where Blizzard's button really sits,
-- under some other cell. Put the cursor where Blizzard's own call would now
-- put it: the stored anchor, set on the cursor frame. Nothing is selected or
-- written to Blizzard's tables.
local function PlaceCursor()
    local nav = _G.SmartNavigation
    local current = nav and nav.currentButton
    if not (current and navAnchored[current]) then return end
    local anchor = _G.SmartNavigation_GetCustomCursorAnchorPointForFrame
        and _G.SmartNavigation_GetCustomCursorAnchorPointForFrame(current)
    if not anchor then return end
    local _, to = nav:GetPoint(1)
    if to == anchor.relativeTo then return end
    anchor:SetPoint(nav, true)
    Note("cursor placed on its cell")
end

local function Ignore(frame)
    if not frame or navIgnored[frame] then return end
    navIgnored[frame] = true
    _G.SmartNavigation_MarkFrameIgnored(frame)
end

local JUMP_HINTS = { "FocusJumpHint", "LeftJumpHint", "RightJumpHint" }

-- Blizzard's frame stays shown, so its buttons stay valid controller targets,
-- and is drawn at nothing. Its prompt bar is kept visible.
function Bags.HideNative()
    local combined = _G.ContainerFrameCombinedBags
    if not (Bags.adopted and combined) then return end
    if combined:GetAlpha() > 0 then combined:SetAlpha(0) end
    local footer = combined.gamepadFooter
    local legend = footer and footer.inputLegend
    if legend and legend.SetIgnoreParentAlpha and not legend:IsIgnoringParentAlpha() then
        legend:SetIgnoreParentAlpha(true)
    end
    -- Blizzard's jump hints: the menu-button icon it shows on the frame that
    -- button would focus again, and the trigger icons on the frames beside
    -- the focused one. Blizzard shows and hides them; they are drawn here at
    -- Blizzard's own place, under the middle of this window's bottom edge.
    if not Bags.Window.IsBuilt() then return end
    local frame = Bags.Window.Frame()
    local level = frame:GetFrameLevel() + 30
    for _, key in ipairs(JUMP_HINTS) do
        local hint = combined[key]
        if hint and hint.SetIgnoreParentAlpha then
            if not hint:IsIgnoringParentAlpha() then hint:SetIgnoreParentAlpha(true) end
            local _, to = hint:GetPoint(1)
            if to ~= frame then
                hint:ClearAllPoints()
                hint:SetPoint("CENTER", frame, "BOTTOM", 0, 4)
            end
            if hint:GetFrameLevel() ~= level then hint:SetFrameLevel(level) end
        end
    end
end

-- bag -> slot -> Blizzard's item button, for the buttons it has laid out.
local function NativeButtons(combined)
    local map = {}
    local items = combined.Items
    if type(items) ~= "table" then return map end
    for _, b in ipairs(items) do
        local bag = b.bagID
        if type(bag) == "number" and b:IsShown() then
            local row = map[bag]
            if not row then
                row = {}
                map[bag] = row
            end
            row[b:GetID()] = b
        end
    end
    return map
end

--- Whether the bag is collapsed: Blizzard's collapse prompt flips a flag on
--- its bag bar button, and what Blizzard does with it is in its hidden frame.
function Bags.IsCollapsed(bag)
    if not Bags.adopted then return false end
    local bar = _G.GamepadBagBar
    local list = bar and bar.BagButtonArray
    local b = list and bag >= 0 and list[bag + 1]
    return b and b.isCollapsed == true or false
end

local function NativeBagButton(bag)
    local bar = _G.GamepadBagBar
    local list = bar and bar.BagButtonArray
    local b = list and bag >= 0 and list[bag + 1]
    if b and b:IsVisible() then return b end
    return nil
end

-- Two of Blizzard's own header pieces stand in this window's header, moved
-- there and not copied, so what they open is Blizzard's code on Blizzard's
-- path. Its portrait button lies over this window's portrait: Y on it opens
-- Blizzard's bag menu, left as Blizzard builds it (menu.lua says why); the
-- gear is hidden under the gamepad UI (window.lua). Its search box lies over
-- this window's, drawn, with its prompt icon; Blizzard puts the box back on
-- every update of its frame, so both are placed again on every build.
-- This window's portrait stops taking the pointer: it
-- opens a menu from this addon's code.
local function Over(native, mine, level)
    local _, to = native:GetPoint(1)
    if to ~= mine or native:GetNumPoints() ~= 2 then
        native:ClearAllPoints()
        native:SetPoint("TOPLEFT", mine, "TOPLEFT", 0, 0)
        native:SetPoint("BOTTOMRIGHT", mine, "BOTTOMRIGHT", 0, 0)
    end
    if native:GetFrameLevel() ~= level then native:SetFrameLevel(level) end
end

local function TieHeader(frame, combined)
    local level = frame:GetFrameLevel() + 30
    local box, mine = _G.BagItemSearchBox, frame._search
    if box and mine and box:GetParent() == combined then
        Over(box, mine, level)
        if not box:IsIgnoringParentAlpha() then box:SetIgnoreParentAlpha(true) end
        mine:SetAlpha(0)
        mine:EnableMouse(false)
        local icon = combined.SearchBoxIcon
        if icon then
            if not icon:IsIgnoringParentAlpha() then icon:SetIgnoreParentAlpha(true) end
            if icon:GetFrameLevel() ~= level then icon:SetFrameLevel(level) end
        end
    end
    local portrait, mine = combined.PortraitButton, frame._portraitButton
    if not (portrait and mine) then return nil end
    mine:EnableMouse(false)
    Over(portrait, mine, level)
    return portrait:IsVisible() and portrait or nil
end

-- A menu Blizzard opens from one of its buttons hangs off that button, which
-- is somewhere under this window. Hang it off the cell or the bag icon.
local function MenuShown(_, menu)
    if not (Bags.adopted and menu and menu.GetOwnerRegion) then return end
    local owner = menu:GetOwnerRegion()
    if not owner then return end
    local parent, mine = owner:GetParent(), nil
    if parent == _G.ContainerFrameCombinedBags and type(owner.bagID) == "number" then
        mine = Bags.Cells.Find(owner.bagID, owner:GetID())
    elseif parent and parent == _G.GamepadBagBar and parent.BagButtonArray then
        for index, button in ipairs(parent.BagButtonArray) do
            if button == owner then
                for _, line in ipairs(Bags.Layout.Lines()) do
                    if line.bag == index - 1 then mine = line.icon end
                end
            end
        end
    end
    if not mine then return end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", mine, "BOTTOMLEFT", 0, 0)
end

local function BuildNav()
    if not (Bags.adopted and Bags.Window.IsBuilt()) then return end
    local dirs = _G.SMART_NAV_INPUT_DIRECTION
    local combined = _G.ContainerFrameCombinedBags
    if not (dirs and combined and _G.CreateAnchor
            and _G.SmartNavigation_AddJumpNavigationOverride
            and _G.SmartNavigation_SetCustomCursorAnchorPointForFrame
            and _G.SmartNavigation_MarkFrameIgnored) then
        return
    end
    local frame = Bags.Window.Frame()
    local content = Bags.Window.Content()
    if not navHolder then
        navHolder = CreateFrame("Frame", nil, content)
        navHolder:SetAllPoints()
        navHolder:SetFrameLevel(content:GetFrameLevel() + 20)
        navBand = content:CreateTexture(nil, "BACKGROUND")
        navBand:SetColorTexture(1, 1, 1, BAND_ALPHA)
        navBand:Hide()
        navGlow = navHolder:CreateTexture(nil, "OVERLAY")
        navGlow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        navGlow:SetBlendMode("ADD")
        navGlow:Hide()
        navHolder:SetScript("OnUpdate", RecordPresses)
        navHolder:SetScript("OnHide", function() wipe(keyDown) end)
    end
    Bags.HideNative()

    -- Nothing in this window is a controller target but the sort button.
    local sort = frame._sort
    for _, child in ipairs({ frame:GetChildren() }) do
        if child ~= sort then Ignore(child) end
    end
    if not (sort and sort:IsShown()) then sort = nil end
    local portrait = TieHeader(frame, combined)

    local map = NativeButtons(combined)
    local cols = Bags.Layout.Columns()

    -- The grid as drawn: grid[row][col] is Blizzard's button for that place.
    -- Column 0 holds a bag's icon on its first line; the slots fill columns 1
    -- to cols, as Layout.Run places them. A collapsed bag is a line holding
    -- its icon alone. A bag Blizzard laid out no buttons for has no lines.
    local grid, lined = {}, {}
    local matched, missing = 0, 0
    for _, line in ipairs(Bags.Layout.Lines()) do
        local row = map[line.bag]
        local icon = NativeBagButton(line.bag)
        if (line.count > 0 and row) or line.collapsed then
            lined[line.bag] = true
            if icon then
                SetCursor(icon, line.icon)
                grid[line.row] = grid[line.row] or {}
                grid[line.row][0] = icon
            end
        end
        if line.count > 0 and row then
            for slot = 1, line.count do
                local b = row[slot]
                local cell = Bags.Cells.Find(line.bag, slot)
                if b and cell then
                    matched = matched + 1
                    SetCursor(b, cell)
                    local r = line.row + math.floor((slot - 1) / cols)
                    grid[r] = grid[r] or {}
                    grid[r][1 + (slot - 1) % cols] = b
                else
                    missing = missing + 1
                end
            end
        end
    end
    -- Rows top to bottom, each its cells left to right, empty rows dropped.
    local rows = {}
    local rowKeys = {}
    for r in pairs(grid) do rowKeys[#rowKeys + 1] = r end
    table.sort(rowKeys)
    for _, r in ipairs(rowKeys) do
        local cells = {}
        for c = 0, cols do
            local b = grid[r][c]
            if b then cells[#cells + 1] = { col = c, button = b } end
        end
        if #cells > 0 then rows[#rows + 1] = cells end
    end

    -- The cell nearest a column in a row; a tie goes left.
    local function Nearest(cells, col)
        if not cells then return nil end
        local best, dist
        for _, c in ipairs(cells) do
            local d = math.abs(c.col - col)
            if not dist or d < dist then best, dist = c.button, d end
        end
        return best
    end

    -- Up from the top row: the portrait over its left half, the sort button
    -- over its right half, either one alone when the other is missing.
    local function Header(col)
        if portrait and sort then return col <= cols / 2 and portrait or sort end
        return portrait or sort
    end
    for i, cells in ipairs(rows) do
        local n = #cells
        for j, c in ipairs(cells) do
            local b = c.button
            SetTarget(b, dirs.LEFT, n > 1 and cells[j > 1 and j - 1 or n].button or true)
            SetTarget(b, dirs.RIGHT, n > 1 and cells[j < n and j + 1 or 1].button or true)
            SetTarget(b, dirs.UP, Nearest(rows[i - 1], c.col) or (i == 1 and Header(c.col)) or true)
            SetTarget(b, dirs.DOWN, Nearest(rows[i + 1], c.col) or true)
        end
    end

    local first = rows[1] and Nearest(rows[1], 1)
    if first then
        -- A bag slot with no bag in it has no line here; the shoulder buttons
        -- can still land on its button, and any direction comes back.
        for bag = 0, NUM_BAG_SLOTS do
            local b = not lined[bag] and NativeBagButton(bag)
            if b then
                SetCursor(b, navHolder)
                SetTarget(b, dirs.LEFT, first)
                SetTarget(b, dirs.RIGHT, first)
                SetTarget(b, dirs.UP, first)
                SetTarget(b, dirs.DOWN, first)
            end
        end
    end
    -- The header: the portrait at the left, the sort button at the right,
    -- each going down to the top row's cell under it and across to the other.
    if sort then
        SetTarget(sort, dirs.DOWN, Nearest(rows[1], cols) or true)
        SetTarget(sort, dirs.UP, true)
        SetTarget(sort, dirs.LEFT, portrait or true)
        SetTarget(sort, dirs.RIGHT, portrait or true)
    end
    if portrait then
        SetTarget(portrait, dirs.DOWN, Nearest(rows[1], 0) or true)
        SetTarget(portrait, dirs.UP, true)
        SetTarget(portrait, dirs.LEFT, sort or true)
        SetTarget(portrait, dirs.RIGHT, sort or true)
    end
    PlaceCursor()
    ShowBag(navCell and navCurrent and navCurrent.bagID or nil)
    navStats.matched, navStats.missing = matched, missing
    navStats.builds = navStats.builds + 1
end

--- Blizzard's setters refuse an addon in combat, so the build waits. Blizzard
--- sets two targets of its own a frame after its window shows, so the build
--- runs again after that.
function Bags.QueueNav()
    addon.Events.RunOutOfCombat(BuildNav, "Bags.nav")
    C_Timer.After(0.2, function()
        addon.Events.RunOutOfCombat(BuildNav, "Bags.nav")
    end)
end

--- Start under the gamepad UI. Without Blizzard's combined frame there is
--- nothing to ride on, and Blizzard's own bag window stays.
function Bags.StartGamepad(comp)
    if Bags.active or not ContainerFrameCombinedBags then return end

    Bags.active = true
    Bags.adopted = true
    InstallOpenPaths()
    Listen(comp)

    Bags.Window.Open()
    local frame = Bags.Window.Frame()
    frame:SetParent(ContainerFrameCombinedBags)
    frame:ClearAllPoints()
    -- Over Blizzard's frame, bottom edges together: Blizzard's prompt bar
    -- hangs under its frame and so sits under this one.
    frame:SetPoint("BOTTOMRIGHT", ContainerFrameCombinedBags, "BOTTOMRIGHT", 0, 0)
    frame:SetIgnoreParentAlpha(true)
    frame:SetFrameLevel(ContainerFrameCombinedBags:GetFrameLevel() + 40)
    local registry = _G.EventRegistry
    if registry then
        registry:RegisterCallback("ContainerFrameItemButton.EnterButton", ItemEntered, Bags)
        registry:RegisterCallback("ContainerFrameItemButton.ExitButton", ItemExited, Bags)
        registry:RegisterCallback("BagSlot.OnEnter", BagEntered, Bags)
        registry:RegisterCallback("BagSlot.OnLeave", BagLeft, Bags)
        registry:RegisterCallback("MenuProxy.OnShow", MenuShown, Bags)
        registry:RegisterCallback("LootFrame.Hide", LootHidden, Bags)
    end
    comp:On("LOOT_OPENED", LootOpened)
    Bags.HideNative()
    -- The close button would close Blizzard's bags from this addon's path,
    -- which runs the gamepad controls manager as the addon.
    if frame.CloseButton then frame.CloseButton:Hide() end
    Bags.Refresh()
end

local function AdoptReport()
    if not addon.DebugLines then return end
    local lines, push = addon.DebugLines("=== Bags under the gamepad UI ===", "")
    push("gamepad active: %s", tostring(GamepadActive()))
    push("adopted: %s", tostring(Bags.adopted or false))
    push("feature on (component built): %s", tostring(Bags.component ~= nil))
    push("window running: %s", tostring(Bags.active or false))
    push("combined frame: %s", tostring(_G.ContainerFrameCombinedBags ~= nil))
    push("bags open: %s", tostring(BagsOpen()))
    local frame = Bags.Window.IsBuilt() and Bags.Window.Frame()
    if frame then
        local parent = frame:GetParent()
        push("window parent: %s", parent and parent:GetName() or "nil")
        push("window visible: %s", tostring(frame:IsVisible()))
    end
    local nav = _G.SmartNavigation
    local function secure(tbl, key)
        local ok, by = _G.issecurevariable(tbl, key)
        return ("%s (%s)"):format(tostring(ok), tostring(by or "Blizzard"))
    end
    if nav then
        local button = nav.currentButton
        local name = button and button.GetName and button:GetName() or nil
        push("cursor on: %s", name or (button and "an unnamed button") or "nothing")
        local ours = name and name:find(addon.Brand .. "Bag", 1, true) == 1
        push("cursor on this window: %s", tostring(ours or false))
        push("currentButton secure: %s", secure(nav, "currentButton"))
        push("activeInfo secure: %s", secure(nav, "activeInfo"))
        local info = nav.activeInfo
        if info then
            push("activeInfo.buttonGroups secure: %s", secure(info, "buttonGroups"))
        end
    else
        push("SmartNavigation: absent")
    end
    push("")
    local manager = BindingManager()
    if manager then
        push("core bindings active: %s", tostring(manager.currentCoreBindingActive))
        local stack = manager.bindingSetStack or {}
        push("binding stack, bottom to top (%d over core):", #stack)
        for i, set in ipairs(stack) do
            push("  %d %s%s%s", i, tostring(set.name), set.treatBindsAsCore and ", as core" or "",
                set.stayOnTop and ", on top" or "")
        end
        local active = manager.activeBindings or {}
        for _, key in ipairs(FACE_KEYS) do
            local owner = active[key]
            push("  %s -> %s (binding %s, active %s)", key, tostring(_G.GetBindingAction(key, true) or ""),
                owner and tostring(owner.buttonToClick or owner.name or owner.key) or "none",
                owner and tostring(owner.isActive) or "-")
        end
    end
    local mode = _G.GamepadMode
    local fcm = mode and mode.FrameControlsManager
    if fcm then
        local focused = fcm.focusedFrame
        push("controls manager: UI focused %s, catcher %s, focused %s%s, shown frames %d",
            tostring(fcm.isUIFocused), tostring(fcm.fallThroughCatcherActive),
            focused and (focused.GetName and focused:GetName() or "unnamed") or "none",
            focused and focused == _G.ContainerFrameCombinedBags and " (the bags)" or "",
            type(fcm.shownFrames) == "table" and #fcm.shownFrames or -1)
    end
    local combinedFooter = _G.ContainerFrameCombinedBags and _G.ContainerFrameCombinedBags.gamepadFooter
    if combinedFooter then
        local prompts = {}
        for _, prompted in ipairs(combinedFooter.promptedBindingsActive or {}) do
            local key = prompted.GetKeyForIndex and prompted:GetKeyForIndex(1)
            local label = prompted.footerBinding and prompted.footerBinding.label
            if type(label) == "function" then label = "(by function)" end
            prompts[#prompts + 1] = ("%s=%s"):format(tostring(key), tostring(label))
        end
        push("bag footer: shown %s, prompts %s", tostring(combinedFooter.isShown),
            #prompts > 0 and table.concat(prompts, " ") or "none")
    end
    push("")
    local taint = Bags.navTaint
    if taint then
        push("binding stack first tainted: %s", taint.set)
        push("  seen %s", taint.when)
        for _, entry in ipairs(taint.log) do push("  before it: %s", entry) end
    else
        push("binding stack taint seen by the recorder: none (now: %s)", StackTaint() or "clean")
    end
    for _, entry in ipairs(navLog) do push("recent: %s", entry) end
    push("")
    push("builds: %d, slots tied to Blizzard's buttons: %d, without one: %d",
        navStats.builds, navStats.matched, navStats.missing)
    local combined = _G.ContainerFrameCombinedBags
    if combined then
        push("Blizzard's frame: shown %s, alpha %.2f", tostring(combined:IsShown()), combined:GetAlpha())
        local footer = combined.gamepadFooter
        local legend = footer and footer.inputLegend
        push("prompt bar: %s", legend and ("shown %s, visible %s"):format(
            tostring(legend:IsShown()), tostring(legend:IsVisible())) or "not built")
    end
    local box = _G.BagItemSearchBox
    if box then
        local _, to = box:GetPoint(1)
        push("Blizzard's search box: on this window's %s, visible %s",
            tostring(Bags.Window.IsBuilt() and to == Bags.Window.Frame()._search), tostring(box:IsVisible()))
    end
    local collapsed = {}
    for _, line in ipairs(Bags.Layout.Lines()) do
        if line.collapsed then collapsed[#collapsed + 1] = tostring(line.bag) end
    end
    local portrait = combined and combined.PortraitButton
    if portrait then
        local _, to = portrait:GetPoint(1)
        push("Blizzard's portrait button: on the portrait %s, visible %s",
            tostring(Bags.Window.IsBuilt() and to == Bags.Window.Frame()._portraitButton), tostring(portrait:IsVisible()))
    end
    push("collapsed bags: %s", #collapsed > 0 and table.concat(collapsed, " ") or "none")
    local on = nav and nav.currentButton
    if on and type(on.bagID) == "number" then
        push("cursor's button: bag %d slot %d", on.bagID, on:GetID())
    end
    if addon.Gamepad and addon.Gamepad.ReportManagers then
        push("")
        addon.Gamepad.ReportManagers(push)
    end
    addon.DebugShowWindow("Bags under the gamepad UI", lines)
end

addon:RegisterDebugCommand({
    name = "bagsnav",
    help = "Bags under the gamepad UI: what the controller is tied to, and whether the binding stack is clean",
    handler = function()
        AdoptReport()
    end,
})

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
