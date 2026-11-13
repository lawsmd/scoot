--------------------------------------------------------------------------------
-- core/components/bags/layout.lua
-- The lines. The left column holds the bag icons and nothing else: each bag
-- starts a new line with its icon in that column, and its slots fill the
-- columns to the right, wrapping onto as many lines as they need. The setting
-- Slots per Row counts item slots only, so a bag of n slots takes
-- ceil(n / Slots per Row) lines and the window is one column wider.
--
-- The icon is drawn the way Blizzard's bag bar draws a bag: the icon under a
-- round mask, inside the bag-border ring (bag-reagent-border for the reagent
-- bag), smaller than a slot. No slot art behind it, so it reads as a label for
-- the line. The icon is half desaturated and shaded to 85 percent; the ring is
-- desaturated and tinted to the window border's bronze (the portrait ring's
-- color), where Blizzard's ring is bright gold.
--
-- The keyring has a window of its own (keyring.lua) and a plain grid of
-- Blizzard's four columns, with no icon.
--------------------------------------------------------------------------------

local _, addon = ...

local Bags = addon.Bags

local Layout = {}
Bags.Layout = Layout

local BACKPACK_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local EMPTY_ICON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local KEYRING_COLUMNS = 4
-- Blizzard's bag bar buttons are 30; 32 here, inside a 37 cell.
local ICON_SIZE = 32
local ICON_DESATURATION = 0.5
local ICON_SHADE = 0.85
-- The bronze of the frame's border, over a desaturated ring. The minimap
-- replica tints LibDBIcon's rings the same (forever/minimap/display.lua).
local RING_TINT = { 0.93, 0.72, 0.46 }

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local icons = addon.Pool.NewIndexed(function()
    local f = CreateFrame("Frame", nil, Bags.Window.Content())
    f:SetSize(Bags.CELL, Bags.CELL)
    f:EnableMouse(false)

    -- CircularItemButtonTemplate's mask, at its insets.
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetSize(ICON_SIZE, ICON_SIZE)
    tex:SetPoint("CENTER")
    local mask = f:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", tex, "TOPLEFT", 2, -2)
    mask:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", -4, 4)
    tex:AddMaskTexture(mask)
    if tex.SetDesaturation then
        tex:SetDesaturation(ICON_DESATURATION)
    else
        tex:SetDesaturated(true)
    end
    tex:SetVertexColor(ICON_SHADE, ICON_SHADE, ICON_SHADE)
    f.icon = tex

    local ring = f:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints(tex)
    ring:SetDesaturated(true)
    ring:SetVertexColor(RING_TINT[1], RING_TINT[2], RING_TINT[3])
    f.ring = ring
    return f
end)

local function BagIcon(bag)
    if Bags.IsBackpack(bag) then return BACKPACK_ICON end
    local inv = C_Container.ContainerIDToInventoryID and C_Container.ContainerIDToInventoryID(bag)
    local tex = inv and GetInventoryItemTexture("player", inv)
    return tex or EMPTY_ICON
end

local function IsReagentBag(bag)
    local held = (Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots) or 4
    return bag > held and not Bags.IsKeyring(bag)
end

local function RingAtlas(bag)
    local atlas = IsReagentBag(bag) and "bag-reagent-border" or "bag-border"
    if HasAtlas(atlas) then return atlas end
    if HasAtlas("bag-border") then return "bag-border" end
    return nil
end

local function PaintIcon(f, bag)
    f.icon:SetTexture(BagIcon(bag))
    local atlas = RingAtlas(bag)
    if atlas then f.ring:SetAtlas(atlas) end
    f.ring:SetShown(atlas ~= nil)
end

-- frame -> "col:row:content" it was last anchored at. A refresh leaves a cell
-- whose place has not changed alone, so a refresh in combat touches no anchor
-- unless a bag changed size.
local placed = setmetatable({}, { __mode = "k" })

local function Place(frame, content, col, row)
    local key = col .. ":" .. row .. ":" .. tostring(content)
    if placed[frame] == key then return end
    placed[frame] = key
    local step = Bags.CELL + Bags.GAP
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", content, "TOPLEFT", col * step, -row * step)
end

function Layout.Columns()
    local cols = math.floor(tonumber(Bags.Get("columns")) or 8)
    return math.max(6, math.min(16, cols))
end

--- Place every line and size the window around them.
function Layout.Run()
    local content = Bags.Window.Content()
    local cols = Layout.Columns()
    local bags = Bags.BagList()
    local drawn = {}
    local row = 0
    for i, bag in ipairs(bags) do
        drawn[bag] = true
        local n = C_Container.GetContainerNumSlots(bag) or 0

        local icon = icons:Get(i)
        PaintIcon(icon, bag)
        Place(icon, content, 0, row)
        icon:Show()

        -- Column 0 is the icon's; the slots start in column 1.
        for slot = 1, n do
            local i0 = slot - 1
            Place(Bags.Cells.Get(bag, slot), content, 1 + i0 % cols, row + math.floor(i0 / cols))
        end
        Bags.Cells.SetCount(bag, n)
        row = row + math.max(1, math.ceil(n / cols))
    end
    icons:HideFrom(#bags + 1)

    -- The keyring's cells belong to its own window.
    if Bags.Keyring and Bags.Keyring.IsShown() then drawn[Bags.KEYRING] = true end
    Bags.Cells.HideOthers(drawn)

    local step = Bags.CELL + Bags.GAP
    Bags.Window.FitContent((cols + 1) * step - Bags.GAP, math.max(row, 1) * step - Bags.GAP)
end

--- The keyring window's grid.
function Layout.RunKeyring()
    local bag = Bags.KEYRING
    if not (bag and Bags.Keyring and Bags.Keyring.IsBuilt()) then return end
    local content = Bags.Keyring.Content()
    local n = Bags.KeyringSize()
    for slot = 1, n do
        local i = slot - 1
        Place(Bags.Cells.Get(bag, slot), content, i % KEYRING_COLUMNS, math.floor(i / KEYRING_COLUMNS))
    end
    Bags.Cells.SetCount(bag, n)
    local rows = math.max(1, math.ceil(n / KEYRING_COLUMNS))
    local step = Bags.CELL + Bags.GAP
    Bags.Keyring.FitContent(KEYRING_COLUMNS * step - Bags.GAP, rows * step - Bags.GAP)
end
