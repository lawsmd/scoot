-- qol.lua - Quality of Life automation (Loot & Vendors)
local addonName, addon = ...

--------------------------------------------------------------------------------
-- DB Helpers
--------------------------------------------------------------------------------

local function getQoL()
    local profile = addon and addon.db and addon.db.profile
    return profile and profile.qol
end

local function ensureQoL()
    if not (addon and addon.db and addon.db.profile) then return nil end
    addon.db.profile.qol = addon.db.profile.qol or {}
    return addon.db.profile.qol
end

--------------------------------------------------------------------------------
-- Merchant Handler (Auto Repair + Sell Grey Items)
--------------------------------------------------------------------------------

local function onMerchantShow()
    local qol = getQoL()
    if not qol then return end

    -- Sell grey items
    if qol.sellGreyItems then
        for bag = 0, 4 do
            local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bag)
            if ok and numSlots then
                for slot = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
                        C_Container.UseContainerItem(bag, slot)
                    end
                end
            end
        end
    end

    -- Auto repair
    if qol.autoRepairMode and qol.autoRepairMode ~= "off" then
        if CanMerchantRepair() then
            local cost, canRepair = GetRepairAllCost()
            if canRepair and cost > 0 then
                local useGuild = (qol.autoRepairMode == "guild")
                if useGuild then
                    -- Try guild repair first, fall back to personal
                    local guildOk = pcall(RepairAllItems, true)
                    if not guildOk then
                        pcall(RepairAllItems, false)
                    end
                else
                    pcall(RepairAllItems, false)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Loot Handler (Faster Auto Loot)
--------------------------------------------------------------------------------

local function onLootReady(autoLoot)
    local qol = getQoL()
    if not qol or not qol.quickLoot then return end

    -- Ensure auto loot CVar is enabled
    if C_CVar and C_CVar.GetCVar then
        local current = C_CVar.GetCVar("autoLootDefault")
        if current ~= "1" then
            pcall(C_CVar.SetCVar, "autoLootDefault", "1")
        end
    end

    -- Loot all items
    local numItems = GetNumLootItems()
    if numItems and numItems > 0 then
        for i = numItems, 1, -1 do
            pcall(LootSlot, i)
        end
    end

    -- Retry once after 100ms to catch any items missed on first pass
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            local count = GetNumLootItems()
            if count and count > 0 then
                for i = count, 1, -1 do
                    pcall(LootSlot, i)
                end
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Quest Log Count
--------------------------------------------------------------------------------

addon.QoL = addon.QoL or {}

local questCountLabel
local questCountInitialized = false

local NON_STANDARD_CLASSIFICATIONS = {
    [Enum.QuestClassification.BonusObjective] = true,
    [Enum.QuestClassification.WorldQuest] = true,
    [Enum.QuestClassification.Calling] = true,
    [Enum.QuestClassification.Meta] = true,
    [Enum.QuestClassification.Recurring] = true,
    [Enum.QuestClassification.Campaign] = true,  -- tracked separately, doesn't count toward cap
}

local function countStandardQuests()
    local ok, numEntries = pcall(C_QuestLog.GetNumQuestLogEntries)
    if not ok or type(numEntries) ~= "number" then return nil, nil end

    local ok2, maxQuests = pcall(C_QuestLog.GetMaxNumQuestsCanAccept)
    if not ok2 or type(maxQuests) ~= "number" then return nil, nil end

    local count = 0
    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden
            and not info.isBounty and not info.isTask then
            if not C_QuestLog.IsWorldQuest(info.questID)
                and not C_QuestLog.IsQuestTask(info.questID) then
                if not NON_STANDARD_CLASSIFICATIONS[info.questClassification] then
                    count = count + 1
                end
            end
        end
    end
    return count, maxQuests
end

local function updateQuestCount()
    if not questCountLabel then return end

    local qol = getQoL()
    if not qol or not qol.showQuestLogCount then
        questCountLabel:Hide()
        return
    end

    if not QuestScrollFrame or not QuestScrollFrame:IsShown() then
        questCountLabel:Hide()
        return
    end

    local numQuests, maxQuests = countStandardQuests()
    if not numQuests or not maxQuests then return end

    questCountLabel:SetText(numQuests .. "/" .. maxQuests .. " Quests")

    local remaining = maxQuests - numQuests
    if remaining <= 0 then
        questCountLabel:SetTextColor(1, 0.2, 0.2)
    elseif remaining <= 3 then
        questCountLabel:SetTextColor(1, 0.82, 0)
    else
        questCountLabel:SetTextColor(0.82, 0.82, 0.82)
    end

    questCountLabel:Show()
end

addon.QoL.updateQuestCount = updateQuestCount

local function initQuestCount()
    if questCountInitialized then return end
    if not QuestScrollFrame then return end

    -- Own overlay frame on the world map title bar, high strata to sit above decorations
    local titleBar = WorldMapFrame and WorldMapFrame.BorderFrame
    if not titleBar then return end

    local holder = CreateFrame("Frame", nil, titleBar)
    holder:SetFrameStrata("DIALOG")
    holder:SetSize(1, 1)
    holder:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", -55, -12)

    questCountLabel = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    questCountLabel:SetFont(questCountLabel:GetFont(), 11, "OUTLINE")
    questCountLabel:SetPoint("RIGHT")

    questCountInitialized = true

    hooksecurefunc(QuestScrollFrame, "Show", function() updateQuestCount() end)
    QuestScrollFrame:HookScript("OnShow", function() updateQuestCount() end)
    QuestScrollFrame:HookScript("OnHide", function()
        if questCountLabel then questCountLabel:Hide() end
    end)

    updateQuestCount()
end

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------

local qolEventFrame = CreateFrame("Frame")
qolEventFrame:RegisterEvent("MERCHANT_SHOW")
qolEventFrame:RegisterEvent("LOOT_READY")
qolEventFrame:RegisterEvent("ADDON_LOADED")
qolEventFrame:RegisterEvent("QUEST_LOG_UPDATE")
qolEventFrame:RegisterEvent("QUEST_ACCEPTED")
qolEventFrame:RegisterEvent("QUEST_REMOVED")
qolEventFrame:RegisterEvent("QUEST_TURNED_IN")

qolEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        onMerchantShow()
    elseif event == "LOOT_READY" then
        onLootReady(...)
    elseif event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == "Blizzard_UIPanels_Game" then
            initQuestCount()
        end
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED"
        or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
        if not questCountInitialized and QuestScrollFrame then
            initQuestCount()
        end
        updateQuestCount()
    end
end)
