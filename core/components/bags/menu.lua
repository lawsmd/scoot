--------------------------------------------------------------------------------
-- core/components/bags/menu.lua
-- The bag window's two menus, both Blizzard's own menu (MenuUtil), so they
-- match the window's art.
--
-- The gear: the settings a player reaches for while the bags are open, since
-- the window is not in Edit Mode. Each one writes the component's setting and
-- applies it at once; Bag Settings opens the full page.
--
-- The portrait: Blizzard's per-bag menu, which the parked combined frame no
-- longer offers. Blizzard's builders are locals of its file, so this is the
-- same menu written against the C API alone; the filter cache Blizzard keeps
-- clears itself on BAG_SLOT_FLAGS_UPDATED.
--------------------------------------------------------------------------------

local _, addon = ...

local Bags = addon.Bags

local Menu = {}
Bags.Menu = Menu

local SIZES = { 75, 90, 100, 110, 125, 150 }
local MIN_COLUMNS, MAX_COLUMNS = 6, 16
local NUM_BAG_SLOTS = (Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots) or 4

local function Set(key, value)
    local comp = Bags.component
    local db = comp and addon:EnsureComponentDB(comp)
    if not db then return end
    db[key] = value
    Bags.ApplySettings()
end

local function IsOn(key)
    return Bags.Get(key) ~= false
end

local function Toggle(key)
    Set(key, not IsOn(key))
end

--------------------------------------------------------------------------------
-- The gear
--------------------------------------------------------------------------------

local function GearMenu(_, root)
    root:CreateTitle("Bags")

    local columns = root:CreateButton("Slots per Row")
    for n = MIN_COLUMNS, MAX_COLUMNS do
        columns:CreateRadio(tostring(n),
            function(value) return (tonumber(Bags.Get("columns")) or 8) == value end,
            function(value) Set("columns", value) end,
            n)
    end

    local size = root:CreateButton("Size")
    for _, pct in ipairs(SIZES) do
        size:CreateRadio(pct .. "%",
            function(value) return (tonumber(Bags.Get("scale")) or 90) == value end,
            function(value) Set("scale", value) end,
            pct)
    end

    root:CreateCheckbox("Show Free Slots",
        function() return IsOn("showFreeSlots") end,
        function() Toggle("showFreeSlots") end)
    root:CreateCheckbox("Show Delete Button",
        function() return IsOn("showDelete") end,
        function() Toggle("showDelete") end)

    root:CreateDivider()
    root:CreateButton("Bag Settings", function()
        if addon.UI and addon.UI.OpenToPage then
            addon.UI:OpenToPage(Bags.COMPONENT_ID)
        end
    end)
end

-- Under the gamepad UI nothing is added to Blizzard's bag menu. Elements this
-- addon adds through Menu.ModifyMenu taint the menu Blizzard builds from them,
-- so its show and close run the controls manager as the addon: the menu never
-- took the controller, and its close was refused. These settings are in the
-- options panel there.

function Menu.OpenGear(owner)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, GearMenu)
    end
end

--------------------------------------------------------------------------------
-- The portrait
--------------------------------------------------------------------------------

local BAG_NAMES = {
    [0] = BAG_NAME_BACKPACK,
    [1] = BAG_NAME_BAG_1,
    [2] = BAG_NAME_BAG_2,
    [3] = BAG_NAME_BAG_3,
    [4] = BAG_NAME_BAG_4,
}

local function BagName(bag)
    return BAG_NAMES[bag] or (C_Container.GetBagName and C_Container.GetBagName(bag)) or tostring(bag)
end

local function AddFilters(description, bag)
    if not (ContainerFrame_CanContainerUseFilterMenu and ContainerFrame_CanContainerUseFilterMenu(bag)) then return end
    if not (ContainerFrameUtil_EnumerateBagGearFilters and BAG_FILTER_LABELS) then return end
    description:CreateTitle(BAG_FILTER_ASSIGN_TO)
    local function IsSelected(flag)
        return C_Container.GetBagSlotFlag(bag, flag)
    end
    local function SetSelected(flag)
        C_Container.SetBagSlotFlag(bag, flag, not IsSelected(flag))
    end
    for _, flag in ContainerFrameUtil_EnumerateBagGearFilters() do
        local checkbox = description:CreateCheckbox(BAG_FILTER_LABELS[flag], IsSelected, SetSelected, flag)
        checkbox:SetResponse(MenuResponse.Close)
    end
end

local function AddIgnore(description, bag)
    local flags = Enum.BagSlotFlags
    local backpack = Bags.IsBackpack(bag)
    description:CreateTitle(BAG_FILTER_IGNORE)

    local function SortIgnored()
        if backpack then return C_Container.GetBackpackAutosortDisabled() end
        return C_Container.GetBagSlotFlag(bag, flags.DisableAutoSort)
    end
    local cleanup = description:CreateCheckbox(BAG_FILTER_CLEANUP, SortIgnored, function()
        local value = not SortIgnored()
        if backpack then
            C_Container.SetBackpackAutosortDisabled(value)
        else
            C_Container.SetBagSlotFlag(bag, flags.DisableAutoSort, value)
        end
    end)
    cleanup:SetResponse(MenuResponse.Close)

    if not (flags.ExcludeJunkSell and SELL_ALL_JUNK_ITEMS_EXCLUDE_FLAG) then return end
    local function JunkIgnored()
        if backpack then return C_Container.GetBackpackSellJunkDisabled() end
        return C_Container.GetBagSlotFlag(bag, flags.ExcludeJunkSell)
    end
    local junk = description:CreateCheckbox(SELL_ALL_JUNK_ITEMS_EXCLUDE_FLAG, JunkIgnored, function()
        local value = not JunkIgnored()
        if backpack then
            C_Container.SetBackpackSellJunkDisabled(value)
        else
            C_Container.SetBagSlotFlag(bag, flags.ExcludeJunkSell, value)
        end
    end)
    junk:SetResponse(MenuResponse.Close)
end

local function PortraitMenu(_, root)
    root:CreateTitle(BAG_FILTER_TITLE_SORTING)
    for bag = 0, NUM_BAG_SLOTS do
        local n = C_Container.GetContainerNumSlots(bag)
        if n and n > 0 then
            local submenu = root:CreateButton(BagName(bag))
            AddFilters(submenu, bag)
            AddIgnore(submenu, bag)
        end
    end
end

function Menu.OpenPortrait(owner)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, PortraitMenu)
    end
end
