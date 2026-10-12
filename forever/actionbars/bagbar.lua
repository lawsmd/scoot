--------------------------------------------------------------------------------
-- forever/actionbars/bagbar.lua
-- The bag bar replica: the backpack, the four bag slots, the reagent bag and
-- the keyring, each a secure click twin of Blizzard's slot (type "click"), so
-- a click opens the bag through Blizzard's own handler, untainted. Blizzard's
-- slots stay parked with BagsBar.
--
-- Two looks, one set of buttons. Forever's is its own bag bar: 45 by 45
-- square slots in ui-hud-actionbar-iconframe-bags (the reagent bag in the
-- action bar icon frame), the icon under the action bar mask, the keyring a
-- 33 by 45 small slot, a divider between slots. Combined draws every slot as
-- a micro button's rectangle: the micro button background at the micro
-- button's size, the bag's icon inside it, in the small slot frame the
-- keyring wears.
--
-- What Blizzard's slot does on its own and the twin has to do itself: the
-- drag (a dragged bag is picked up, a dropped item or bag is put in), the
-- tooltip, the icon off the equipped bag, the backpack's free slot count and
-- the open-bag highlight. None of those calls is protected.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local MicroBags = ActionBars.MicroBags

local Bags = {}
MicroBags.Bags = Bags

-- From the anchor end outward, Blizzard's registration order. inv is the
-- inventory slot name GetInventorySlotInfo takes; bag the container index.
Bags.SLOTS = {
    { key = "backpack", blizz = "MainMenuBarBackpackButton", bag = 0, label = "Backpack",
      command = "TOGGLEBACKPACK" },
    { key = "bag1", blizz = "CharacterBag0Slot", inv = "Bag0Slot", bag = 1, label = "Bag 1", command = "TOGGLEBAG4" },
    { key = "bag2", blizz = "CharacterBag1Slot", inv = "Bag1Slot", bag = 2, label = "Bag 2", command = "TOGGLEBAG3" },
    { key = "bag3", blizz = "CharacterBag2Slot", inv = "Bag2Slot", bag = 3, label = "Bag 3", command = "TOGGLEBAG2" },
    { key = "bag4", blizz = "CharacterBag3Slot", inv = "Bag3Slot", bag = 4, label = "Bag 4", command = "TOGGLEBAG1" },
    { key = "reagent", blizz = "CharacterReagentBag0Slot", inv = "ReagentBag0Slot", bag = 5, label = "Reagent Bag",
      command = "TOGGLEREAGENTBAG1" },
    { key = "keyring", blizz = "KeyRingButton", label = "Keyring", keyring = true },
}

-- Forever's numbers (its Camelot MainMenuBarBagButtons.xml and .lua).
Bags.SLOT_SIZE = 45
Bags.KEYRING_WIDTH = 33
Bags.FRAME_SIZE = 46
Bags.BAG_FRAME = "ui-hud-actionbar-iconframe-bags"
Bags.REAGENT_FRAME = "UI-HUD-ActionBar-IconFrame"
Bags.KEYRING_FRAME = "UI-HUD-ActionBar-IconFrame-Small"
Bags.MASK = "UI-HUD-ActionBar-IconFrame-Mask"
Bags.BACKPACK_ICON = "Interface\\Icons\\ui-hud-actionbar-bag"
-- The Combined rectangle: the micro button's background, and around the
-- icon the small slot frame. A first choice for the beta to judge.
Bags.COMBINED_BG = "UI-HUD-MicroMenu-ButtonBG-Up"
Bags.COMBINED_BG_DOWN = "UI-HUD-MicroMenu-ButtonBG-Down"
Bags.COMBINED_FRAME = "UI-HUD-ActionBar-IconFrame-Small"
Bags.COMBINED_ICON_INSET = 5

local buttons = {}   -- in Bags.SLOTS order
local byKey = {}
Bags.Buttons = buttons

--------------------------------------------------------------------------------
-- State reads
--------------------------------------------------------------------------------

local function invSlotId(slot)
    if not slot.inv then return nil end
    local id = GetInventorySlotInfo(slot.inv)
    return id
end

local function HasKeyring()
    return C_ActionBar and C_ActionBar.ShouldShowKeyring and C_ActionBar.ShouldShowKeyring() or false
end

-- The icon a slot draws: the backpack's fixed icon, the equipped bag's, an
-- empty slot's placeholder, or the keyring's atlas.
local function SetIcon(btn)
    local slot = btn.slot
    local icon = btn.icon
    if slot.key == "backpack" then
        icon:SetTexture(Bags.BACKPACK_ICON)
    elseif slot.keyring then
        icon:SetAtlas(GetCVarBool("showKeyring") and "UI-HUD-ActionBar-Keyring-Small"
            or "UI-HUD-ActionBar-IconFrame-Slot-Small")
    else
        local id, empty = GetInventorySlotInfo(slot.inv)
        local tex = id and GetInventoryItemTexture("player", id)
        icon:SetTexture(tex or empty)
    end
end

local function UpdateFreeSlots(btn)
    local free = C_Container.CalculateTotalNumberOfFreeBagSlots()
    btn.freeSlots = free
    btn.Count:SetText("(" .. free .. ")")
end

-- The open-bag highlight Blizzard's slot carries; read off it, a frame after
-- the container frame's callback has set it.
local function SyncHighlight(btn)
    local blizzHighlight = btn.blizz and btn.blizz.SlotHighlightTexture
    btn.SlotHighlight:SetShown(blizzHighlight and blizzHighlight:IsShown() or false)
end

--------------------------------------------------------------------------------
-- Scripts
--------------------------------------------------------------------------------

local function AppendBinding(command)
    local key = command and GetBindingKey(command)
    if key then
        GameTooltip:AppendText(NORMAL_FONT_COLOR:WrapTextInColorCode(" (" .. GetBindingText(key) .. ")"))
    end
end

-- BaseBagSlotButtonMixin:OnEnterInternal, the backpack's and the keyring's.
local function OnEnter(btn)
    local slot = btn.slot
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    if slot.key == "backpack" then
        GameTooltip_SetTitle(GameTooltip, BACKPACK_TOOLTIP)
        AppendBinding(slot.command)
        GameTooltip:AddLine(NUM_FREE_SLOTS:format(btn.freeSlots or 0))
    elseif slot.keyring then
        GameTooltip:SetText(KEYRING, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
    elseif GameTooltip:SetInventoryItem("player", invSlotId(slot)) then
        AppendBinding(slot.command)
    else
        local reagent = ContainerFrame_IsReagentBag and ContainerFrame_IsReagentBag(slot.bag)
        GameTooltip_SetTitle(GameTooltip, reagent and EQUIP_CONTAINER_REAGENT or EQUIP_CONTAINER)
    end
    GameTooltip:Show()
end

local function OnLeave()
    GameTooltip:Hide()
    ResetCursor()
end

local function OnDragStart(btn)
    local id = invSlotId(btn.slot)
    if id then PickupBagFromSlot(id) end
end

local function OnReceiveDrag(btn)
    local slot = btn.slot
    if slot.key == "backpack" then
        PutItemInBackpack()
    elseif slot.keyring then
        if CursorHasItem() and PutKeyInKeyRing then PutKeyInKeyRing() end
    else
        local id = invSlotId(slot)
        if id then PutItemInBag(id) end
    end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

-- The parent is the strip microbags.lua creates, a Camelot frame, so the
-- secure child protects only Camelot's own holders.
local function Twin(parent, slot)
    local blizz = _G[slot.blizz]
    if not blizz then return nil end
    local btn = CreateFrame("Button", "Camelot" .. slot.blizz, parent, "SecureActionButtonTemplate")
    btn.slot = slot
    btn.blizz = blizz
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("type", "click")
    btn:SetAttribute("clickbutton", blizz)
    btn:SetAttribute("useOnKeyDown", false)
    btn:RegisterForDrag("LeftButton")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("CENTER")
    btn.Background = bg

    local icon = btn:CreateTexture(nil, "BORDER")
    btn.icon = icon
    local mask = btn:CreateMaskTexture(nil, "OVERLAY")
    mask:SetAtlas(Bags.MASK)
    mask:SetPoint("CENTER", icon, "CENTER")
    icon:AddMaskTexture(mask)
    btn.IconMask = mask

    -- The slot frame is the normal and pushed texture, as Blizzard's is.
    btn:SetNormalAtlas(Bags.BAG_FRAME)
    btn:SetPushedAtlas(Bags.BAG_FRAME)
    btn:SetHighlightAtlas(Bags.BAG_FRAME, "ADD")
    btn:GetHighlightTexture():SetAlpha(0.4)

    local highlight = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    highlight:SetAllPoints()
    highlight:Hide()
    btn.SlotHighlight = highlight

    local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.Count = count

    btn:SetScript("OnEnter", OnEnter)
    btn:SetScript("OnLeave", OnLeave)
    btn:SetScript("OnDragStart", OnDragStart)
    btn:SetScript("OnReceiveDrag", OnReceiveDrag)
    return btn
end

--- Draw every slot in a look: "forever" or "combined". Out of combat: the
--- sizes are a protected frame's.
function Bags.ApplyLook(look, vertical)
    local Micro = MicroBags.Micro
    for _, btn in ipairs(buttons) do
        local slot = btn.slot
        local normal, pushed = btn:GetNormalTexture(), btn:GetPushedTexture()
        local hl = btn:GetHighlightTexture()
        btn.icon:ClearAllPoints()
        btn.Count:ClearAllPoints()
        if look == "combined" then
            btn:SetSize(Micro.WIDTH, Micro.HEIGHT)
            btn.Background:SetAtlas(Bags.COMBINED_BG)
            btn.Background:SetAllPoints()
            btn.Background:Show()
            for _, t in ipairs({ normal, pushed, hl }) do
                t:SetAtlas(Bags.COMBINED_FRAME)
                t:ClearAllPoints()
                t:SetAllPoints()
                t:SetRotation(0)
            end
            local inset = Bags.COMBINED_ICON_INSET
            btn.icon:SetPoint("TOPLEFT", inset, -inset)
            btn.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
            -- A square icon in a tall rectangle: crop the sides to its aspect.
            local w, h = Micro.WIDTH - 2 * inset, Micro.HEIGHT - 2 * inset
            local crop = (1 - w / h) / 2
            btn.icon:SetTexCoord(crop, 1 - crop, 0, 1)
            btn.IconMask:SetSize(w, h)
            btn.SlotHighlight:SetAtlas(Bags.COMBINED_FRAME)
            btn.Count:SetPoint("BOTTOM", 0, 3)
        else
            local frame = slot.key == "reagent" and Bags.REAGENT_FRAME
                or slot.keyring and Bags.KEYRING_FRAME or Bags.BAG_FRAME
            local width = slot.keyring and Bags.KEYRING_WIDTH or Bags.SLOT_SIZE
            local rotate = slot.keyring and vertical
            if rotate then
                btn:SetSize(Bags.SLOT_SIZE, width)
            else
                btn:SetSize(width, Bags.SLOT_SIZE)
            end
            btn.Background:Hide()
            local frameWidth = slot.keyring and Bags.KEYRING_WIDTH or Bags.FRAME_SIZE
            for _, t in ipairs({ normal, pushed }) do
                t:SetAtlas(frame)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", btn, "TOPLEFT")
                t:SetSize(frameWidth, Bags.FRAME_SIZE)
                t:SetRotation(rotate and math.pi / 2 or 0)
            end
            hl:SetAtlas(frame)
            hl:ClearAllPoints()
            hl:SetAllPoints()
            hl:SetRotation(rotate and math.pi / 2 or 0)
            btn.icon:SetAllPoints()
            btn.icon:SetTexCoord(0, 1, 0, 1)
            btn.IconMask:SetSize(btn:GetWidth(), btn:GetHeight())
            btn.SlotHighlight:SetAtlas(frame)
            if slot.key == "backpack" or slot.keyring then
                btn.Count:SetPoint("CENTER", 0, -10)
            else
                btn.Count:SetPoint("BOTTOMRIGHT", -2, 2)
            end
        end
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.4)
        SetIcon(btn)
    end
end

--- The twins that draw, in layout order: Blizzard's slot is shown, the
--- player has not hidden it, and the keyring only where the client has one.
function Bags.Visible()
    local list = {}
    for _, btn in ipairs(buttons) do
        local slot = btn.slot
        local shown = btn.blizz:IsShown() and MicroBags.SlotShown(slot.key)
        if slot.keyring then shown = shown and HasKeyring() end
        if shown then list[#list + 1] = btn end
    end
    return list
end

function Bags.HasKeyring()
    return HasKeyring()
end

--- The backpack's free slot count follows its setting.
function Bags.ApplyCount()
    local backpack = byKey.backpack
    if backpack then backpack.Count:SetShown(MicroBags.Get("slots.backpack.freeSlots") ~= false) end
end

local function RefreshIcons()
    for _, btn in ipairs(buttons) do SetIcon(btn) end
    if byKey.backpack then UpdateFreeSlots(byKey.backpack) end
end

--- Build the twins into the strip, once, out of combat.
function Bags.Build(strip)
    if #buttons > 0 then return end
    for _, slot in ipairs(Bags.SLOTS) do
        local btn = Twin(strip, slot)
        if btn then
            buttons[#buttons + 1] = btn
            byKey[slot.key] = btn
        end
    end
    RefreshIcons()
    Bags.ApplyCount()

    local owner = ActionBars.OWNER .. ".bags"
    addon.Events.On(owner, "PLAYER_ENTERING_WORLD", RefreshIcons)
    addon.Events.On(owner, "BAG_UPDATE_DELAYED", RefreshIcons)
    addon.Events.On(owner, "PLAYER_EQUIPMENT_CHANGED", RefreshIcons)
    addon.Events.On(owner, "BAG_UPDATE", function()
        if byKey.backpack then UpdateFreeSlots(byKey.backpack) end
        if byKey.keyring then SetIcon(byKey.keyring) end
    end)
    local function highlights()
        C_Timer.After(0, function()
            for _, btn in ipairs(buttons) do SyncHighlight(btn) end
        end)
    end
    EventRegistry:RegisterCallback("ContainerFrame.OpenBag", highlights, Bags)
    EventRegistry:RegisterCallback("ContainerFrame.CloseBag", highlights, Bags)
end

--- One line per twin for /camelot actionbars.
function Bags.Report(push)
    for _, btn in ipairs(buttons) do
        push("    %-26s blizz shown %-5s twin shown %-5s %.0fx%.0f", btn.blizz:GetName(),
            tostring(btn.blizz:IsShown()), tostring(btn:IsShown()), btn:GetWidth(), btn:GetHeight())
    end
    push("    keyring on this client: %s", tostring(HasKeyring()))
end
