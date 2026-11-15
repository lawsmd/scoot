--------------------------------------------------------------------------------
-- core/components/bags/delete.lua
-- The delete button: one small close button, Blizzard's x, that moves to the
-- top-right corner of the cell under the mouse, in either window. It is
-- parented to that cell, so it takes the window's scale and hides with it.
-- The setting showDelete turns it off.
--
-- It takes two clicks. At rest the x is gray. The first click arms it: the x
-- turns red and the cell takes a red wash. The second click picks the item up
-- and deletes it. Leaving the cell, moving to another cell, or the slot's item
-- changing puts it back to gray. The tooltip names the step.
--
-- An item the game guards with typed DELETE (Rare and above, not Heirloom,
-- the rule HandleDeleteItemConfirm applies) opens Blizzard's DELETE_GOOD_ITEM
-- dialog on the second click instead, with the item on the cursor; its cancel
-- puts the item back.
--------------------------------------------------------------------------------

local _, addon = ...

local Bags = addon.Bags

local Delete = {}
Bags.Delete = Delete

local SIZE = 14

local button
local target   -- the cell the button sits on
local armed    -- the item link the first click armed, on target

local function NeedsTypedConfirm(quality)
    if not quality or not Enum.ItemQuality then return false end
    return quality >= Enum.ItemQuality.Rare and quality ~= Enum.ItemQuality.Heirloom
end

local function ShowDialog(name, link)
    if StaticPopupDialogs and StaticPopupDialogs[name] then
        StaticPopup_Show(name, link)
        return true
    end
    return false
end

local function DeleteItem(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or info.isLocked then return end
    ClearCursor()
    C_Container.PickupContainerItem(bag, slot)
    if not CursorHasItem() then return end

    if NeedsTypedConfirm(info.quality) then
        local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
        local startsQuest = quest and quest.questID ~= nil
        if startsQuest and ShowDialog("DELETE_GOOD_QUEST_ITEM", info.hyperlink) then return end
        if ShowDialog("DELETE_GOOD_ITEM", info.hyperlink) then return end
        if ShowDialog("DELETE_ITEM", info.hyperlink) then return end
        ClearCursor()
        return
    end
    DeleteCursorItem()
end

local function ItemLink(cell)
    local info = C_Container.GetContainerItemInfo(cell:GetBagID(), cell:GetID())
    return info and info.hyperlink, info
end

local function PaintStep()
    if not button then return end
    local isArmed = armed ~= nil
    for _, tex in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(), button:GetHighlightTexture() }) do
        if tex then tex:SetDesaturated(not isArmed) end
    end
    button._wash:SetShown(isArmed)
end

local function ShowTooltip()
    if not button or not button:IsMouseOver() then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, DELETE or "Delete", HIGHLIGHT_FONT_COLOR)
    if armed then
        GameTooltip_AddErrorLine(GameTooltip, "Click again to delete.")
    else
        GameTooltip_AddNormalLine(GameTooltip, "Click twice to delete.")
    end
    GameTooltip:Show()
end

local function OnClick()
    if not target then return end
    local link = ItemLink(target)
    if not link then
        Delete.Hide()
        return
    end
    if armed ~= link then
        armed = link
        PaintStep()
        ShowTooltip()
        return
    end
    local cell = target
    Delete.Hide()
    DeleteItem(cell:GetBagID(), cell:GetID())
end

local function Build()
    if button then return end
    button = CreateFrame("Button", nil, UIParent, "UIPanelCloseButtonNoScripts")
    button:SetSize(SIZE, SIZE)
    -- The armed wash over the cell: a texture of the button's, anchored to
    -- the cell, so it draws over the item's icon.
    local wash = button:CreateTexture(nil, "BACKGROUND")
    wash:SetColorTexture(0.9, 0.05, 0.05, 0.35)
    wash:Hide()
    button._wash = wash
    button:SetScript("OnClick", OnClick)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        Delete.MaybeHide()
    end)
    button:Hide()
end

--- Put the button on a cell that holds an item it can delete. Coming back to
--- the armed cell from its button keeps the step.
--- over: a frame of a higher strata lying on the cell (the Pick Lock overlay);
--- the button goes over it, so it still takes the mouse.
function Delete.Attach(cell, over)
    if Bags.Get("showDelete") == false then return end
    local link, info = ItemLink(cell)
    if not info or info.isLocked then
        Delete.Hide()
        return
    end
    Build()
    if cell ~= target or link ~= armed then armed = nil end
    target = cell
    button:SetParent(cell)
    if over then
        button:SetFrameStrata(over:GetFrameStrata())
        button:SetFrameLevel(over:GetFrameLevel() + 5)
    else
        button:SetFrameStrata(cell:GetFrameStrata())
        button:SetFrameLevel(cell:GetFrameLevel() + 5)
    end
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 3, 3)
    button._wash:ClearAllPoints()
    button._wash:SetAllPoints(cell)
    PaintStep()
    button:Show()
end

function Delete.Hide()
    target = nil
    armed = nil
    if not button then return end
    if GameTooltip:GetOwner() == button then GameTooltip:Hide() end
    PaintStep()
    button:Hide()
end

--- Hide once the mouse is on neither the cell nor the button. A frame later,
--- so moving from the cell onto the button does not count as leaving.
function Delete.MaybeHide()
    C_Timer.After(0, function()
        if not button or not button:IsShown() then return end
        if button:IsMouseOver() then return end
        if target and target:IsMouseOver() then return end
        Delete.Hide()
    end)
end
