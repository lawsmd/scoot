--------------------------------------------------------------------------------
-- core/components/bags/window.lua
-- The bag window's frame, in Blizzard's art on both clients: the frame is
-- PortraitFrameFlatTemplate, the template ContainerFrameCombinedBags inherits,
-- with the bag portrait, the title, the search box, the sort button and the
-- coin box where Blizzard puts them, and Blizzard's numbers for the insets.
-- The gear left of the sort button opens the settings menu (menu.lua); the
-- portrait opens the per-bag filter menu, as Blizzard's does. On a client with
-- a keyring, a button at the coin box's left opens the keyring window.
--
-- Kept off addon.UI.WindowShell: the window is Blizzard's template, not the
-- skin's. Window.NewFrame is the shell both bag windows share (this one and
-- the keyring's): the template, the close callback, the drag on the title
-- plate and the saved position, in the shape WindowShell writes.
--
-- Built on first open, not at load.
--------------------------------------------------------------------------------

local _, addon = ...

local Bags = addon.Bags

local Window = {}
Bags.Window = Window

-- ContainerFrameCombinedBagsMixin: 15 of width beside the items, the items 8
-- from the right edge; 75 above them; the coin box 8 from the bottom and the
-- items 4 above it.
Window.PAD_LEFT = 7
Window.PAD_TOP = 75
Window.MONEY_INSET = 8
Window.MONEY_GAP = 4
Window.EXTRA_WIDTH = 15

local BACKPACK_PORTRAIT = "Interface/Icons/Inv_misc_bag_08"

-- Blizzard's sort button; the gear takes the same size.
local SORT_W, SORT_H = 28, 26
local SORT_RIGHT, SORT_TOP = 9, 34
local HEADER_GAP = 2

local frame

function Window.IsBuilt()
    return frame ~= nil
end

function Window.Frame()
    return frame
end

--- The frame the lines are drawn on; Layout sizes the window around it.
function Window.Content()
    return frame and frame._content
end

--------------------------------------------------------------------------------
-- The shared frame
--------------------------------------------------------------------------------

local function SavePosition(f, key)
    if not key or not (addon.db and addon.db.global) then return end
    local point, _, relPoint, x, y = f:GetPoint()
    if not point then return end
    addon.db.global[key] = { point = point, relPoint = relPoint, x = x, y = y }
end

--- True when a position was saved and put back.
local function RestorePosition(f, key)
    local pos = key and addon.db and addon.db.global and addon.db.global[key]
    if type(pos) ~= "table" or not (pos.point and pos.x and pos.y) then return false end
    f:ClearAllPoints()
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    return true
end

--- A bag window on Blizzard's portrait frame template.
--- opts: name, portrait, title, onClose, positionKey.
function Window.NewFrame(opts)
    local f = CreateFrame("Frame", opts.name, UIParent, "PortraitFrameFlatTemplate")
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()

    if opts.portrait and f.SetPortraitToAsset then f:SetPortraitToAsset(opts.portrait) end
    if f.SetTitle then f:SetTitle(opts.title) end

    -- The template's close button calls this and hides the frame only when
    -- it returns true. Blizzard's bags close through CloseAllBags and the
    -- window follows the open state.
    f.onCloseCallback = function()
        opts.onClose()
        return false
    end

    local drag = CreateFrame("Button", nil, f.TitleContainer or f)
    drag:SetAllPoints(f.TitleContainer or f)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SavePosition(f, opts.positionKey)
    end)

    f._restored = RestorePosition(f, opts.positionKey)

    local content = CreateFrame("Frame", nil, f)
    content:SetSize(1, 1)
    f._content = content
    return f
end

--------------------------------------------------------------------------------
-- The bag window's pieces
--------------------------------------------------------------------------------

local function ApplySearch(text)
    if C_Container.SetItemSearch then C_Container.SetItemSearch(text or "") end
end

-- SearchBoxTemplate for the look. BagSearchBoxTemplate's handler copies the
-- text into Blizzard's own search boxes, so this box sends its text to
-- SetItemSearch itself.
local function BuildSearch()
    local search = CreateFrame("EditBox", addon.Brand .. "BagWindowSearchBox", frame, "SearchBoxTemplate")
    search:SetHeight(18)
    search:SetAutoFocus(false)
    search:SetMaxLetters(15)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", 62, -37)
    search:HookScript("OnTextChanged", function(self)
        ApplySearch(self:GetText())
    end)
    frame._search = search
end

local function BuildSort()
    local sort = CreateFrame("Button", nil, frame)
    sort:SetSize(SORT_W, SORT_H)
    sort:SetNormalAtlas("bags-button-autosort-up")
    sort:SetPushedAtlas("bags-button-autosort-down")
    local hl = sort:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    hl:SetSize(24, 23)
    hl:SetPoint("CENTER")
    sort:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SORT_RIGHT, -SORT_TOP)
    sort:SetScript("OnClick", function()
        if SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then PlaySound(SOUNDKIT.UI_BAG_SORTING_01) end
        if C_Container.SortBags then C_Container.SortBags() end
    end)
    sort:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self)
        GameTooltip_SetTitle(GameTooltip, BAG_CLEANUP_BAGS or "Clean Up Bags", HIGHLIGHT_FONT_COLOR)
        if BAG_CLEANUP_BAGS_DESCRIPTION then
            GameTooltip_AddNormalLine(GameTooltip, BAG_CLEANUP_BAGS_DESCRIPTION)
        end
        GameTooltip:Show()
    end)
    sort:SetScript("OnLeave", GameTooltip_Hide)
    frame._sort = sort
end

-- The gear wears the sort button's own art, so the two match in size, frame
-- and shadow: the sort atlas as the frame, a gear icon over its picture. The
-- atlas is 62 square; its frame's inner edge sits 12 in from each side. The
-- icon is on OVERLAY: a button's normal and pushed textures draw on ARTWORK,
-- and at the same layer and sublevel the sort picture can cover the gear.
local ICON_INSET_X = SORT_W * 12 / 62
local ICON_INSET_Y = SORT_H * 12 / 62
local GEAR_ICON = "Interface/Icons/INV_Misc_Gear_01"

local function BuildGear()
    local gear = CreateFrame("Button", nil, frame)
    gear:SetSize(SORT_W, SORT_H)
    gear:SetNormalAtlas("bags-button-autosort-up")
    gear:SetPushedAtlas("bags-button-autosort-down")
    local icon = gear:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(GEAR_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local function PlaceIcon(dx, dy)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", ICON_INSET_X + dx, -ICON_INSET_Y + dy)
        icon:SetPoint("BOTTOMRIGHT", -ICON_INSET_X + dx, ICON_INSET_Y + dy)
    end
    PlaceIcon(0, 0)
    local hl = gear:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface/Buttons/ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    hl:SetSize(24, 23)
    hl:SetPoint("CENTER")
    gear:SetScript("OnMouseDown", function() PlaceIcon(1, -1) end)
    gear:SetScript("OnMouseUp", function() PlaceIcon(0, 0) end)
    gear:SetScript("OnClick", function(self) Bags.Menu.OpenGear(self) end)
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, SETTINGS or "Settings", HIGHLIGHT_FONT_COLOR)
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", GameTooltip_Hide)
    frame._gear = gear
end

-- Blizzard's portrait is a menu button too: the round highlight over the
-- bag icon and, on a click, the per-bag filter menu.
local function BuildPortraitButton()
    local portrait = frame.PortraitContainer and frame.PortraitContainer.portrait
    if not portrait then return end
    local btn = CreateFrame("Button", nil, frame)
    btn:SetSize(50, 40)
    btn:SetPoint("CENTER", portrait, "CENTER", 3, -3)
    btn:SetFrameLevel((frame.PortraitContainer:GetFrameLevel() or 400) + 1)
    btn:SetHighlightAtlas("bags-roundhighlight", "ADD")
    btn:SetScript("OnClick", function(self) Bags.Menu.OpenPortrait(self) end)
    frame._portraitButton = btn
end

-- The coin box: Blizzard's own money frame template, named because its coin
-- buttons take their names from it. The free slot count sits at its left.
local function BuildMoney()
    local money = CreateFrame("Frame", addon.Brand .. "BagWindowMoneyFrame", frame, "ContainerMoneyFrameTemplate")
    frame._money = money

    local free = money:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    free:SetPoint("LEFT", money, "LEFT", 6, 0)
    free:SetJustifyH("LEFT")
    frame._free = free
end

local function MoneyHeight()
    local h = frame._money and frame._money:GetHeight()
    return (h and h > 0) and h or 17
end

-- The keyring's one way in, on a client that has a keyring: a plain button at
-- the coin box's left. The coin box starts after it.
local function BuildKeyringButton()
    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btn:SetText(KEYRING or "Keyring")
    local fs = btn:GetFontString()
    btn:SetSize(math.ceil((fs and fs:GetStringWidth() or 50) + 24), 20)
    btn:SetScript("OnClick", function() Bags.Keyring.Toggle() end)
    frame._keyringButton = btn
end

-- The footer row: the keyring button, when shown, then the coin box to the
-- right edge, both centered on the coin box's line.
local function PlaceFooter()
    local money, btn = frame._money, frame._keyringButton
    local inset = Window.MONEY_INSET
    local showKey = Bags.HasKeyring()
    btn:SetShown(showKey)
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", frame, "BOTTOMLEFT", inset, inset + MoneyHeight() / 2)
    money:ClearAllPoints()
    local left = showKey and (inset + btn:GetWidth() + 4) or inset
    money:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", left, inset)
    money:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
end

local function Build()
    if frame then return end
    frame = Window.NewFrame({
        name = addon.Brand .. "BagWindow",
        portrait = BACKPACK_PORTRAIT,
        title = COMBINED_BAG_TITLE or "Combined Backpack",
        onClose = function() Bags.CloseAll() end,
        positionKey = "bagWindowPosition",
    })

    -- Blizzard's spot when nothing is saved: the bottom right, over the bars.
    if not frame._restored then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 110)
    end

    frame._content:SetPoint("TOPLEFT", frame, "TOPLEFT", Window.PAD_LEFT, -Window.PAD_TOP)

    BuildSort()
    BuildGear()
    BuildSearch()
    BuildPortraitButton()
    BuildMoney()
    BuildKeyringButton()

    frame:HookScript("OnShow", function()
        PlaceFooter()
        if Bags.PickLock then Bags.PickLock.Queue() end
    end)
    frame:HookScript("OnHide", function()
        if Bags.Keyring then Bags.Keyring.Close() end
        if Bags.Delete then Bags.Delete.Hide() end
        if Bags.PickLock then Bags.PickLock.HideAll() end
        local search = frame._search
        if search:GetText() ~= "" then search:SetText("") end
        search:ClearFocus()
    end)

    Window.ApplySettings()
end

--- Scale and the optional pieces.
function Window.ApplySettings()
    if not frame then return end
    local scale = tonumber(Bags.Get("scale")) or 90
    frame:SetScale(math.max(0.5, math.min(2, scale / 100)))

    -- The search box runs from Blizzard's left edge to the gear. Both its
    -- anchors are top corners, so its height stays its own.
    local showSort = Bags.Get("showSortButton") ~= false
    frame._sort:SetShown(showSort)
    frame._gear:ClearAllPoints()
    local gearRight = showSort and (SORT_RIGHT + SORT_W + HEADER_GAP) or SORT_RIGHT
    frame._gear:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -gearRight, -SORT_TOP)
    frame._search:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(gearRight + SORT_W + 8), -37)

    frame._free:SetShown(Bags.Get("showFreeSlots") ~= false)
    PlaceFooter()
end

--- The window's size around content of the given size.
function Window.FitContent(width, height)
    if not frame then return end
    frame._content:SetSize(math.max(1, width), math.max(1, height))
    local w = width + Window.EXTRA_WIDTH
    local h = Window.PAD_TOP + height + Window.MONEY_GAP + MoneyHeight() + Window.MONEY_INSET
    frame:SetSize(math.max(w, 240), h)
end

--- The free slot count. The coin box updates itself on PLAYER_MONEY.
function Window.UpdateFooter()
    if not frame then return end
    local free = C_Container.CalculateTotalNumberOfFreeBagSlots and C_Container.CalculateTotalNumberOfFreeBagSlots() or 0
    local fmt = NUM_FREE_SLOTS or "(%s free)"
    frame._free:SetText(fmt:format(free))
end

function Window.Open()
    Build()
    if frame:IsShown() then return end
    Bags.Refresh()
    frame:Show()
end

function Window.Close()
    if not frame or not frame:IsShown() then return end
    frame:Hide()
end
