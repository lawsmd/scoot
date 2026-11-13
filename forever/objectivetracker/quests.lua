--------------------------------------------------------------------------------
-- forever/objectivetracker/quests.lua
-- The quest objects and the POI buttons the Camelot modules use, in place of
-- the ones Blizzard's quest module shares with the world map.
--
-- Blizzard's quest module asks QuestCache for a quest object on every layout
-- (BuildQuestWatchInfos), and QuestCache creates the object on the first ask.
-- QuestCache is one plain table for the whole UI. The world map's quest pins
-- read the same objects: QuestDataProviderMixin:AddQuest styles each pin
-- through POIButtonUtil.GetStyle, which asks QuestCache. With the modules on
-- Camelot's frames the first ask is Camelot's, so the object is written by
-- addon code, and the map's pin refresh runs as the addon from that read on.
-- The map rebuilds its quest pins on every supertrack change once it has been
-- shown, hidden or not, and in combat each pin acquired after the read is
-- refused SetPassThroughButtons, with a stack that is all Blizzard's
-- (the tracker's doc, "Shared objects"; the taint doc, Rule 19).
--
-- So no Camelot module asks QuestCache. The quest modules read the objects
-- below, QuestMixin transcribed over a table of Camelot's own, and every
-- block's POI button comes from a pool here whose buttons answer
-- GetQuestClassification from the client, where Blizzard's button asks
-- QuestCache.
--
-- Transcribed from the Forever build 1.60.1.70790 (docs/camelot/pulls/):
-- Blizzard_ObjectAPI/Mainline/Quest.lua, Blizzard_QuestObjectiveTracker.lua,
-- Blizzard_AutoQuestPopUpTracker.lua and
-- Blizzard_ObjectiveTrackerQuestPOIBlock.lua.
--------------------------------------------------------------------------------

local addonName, addon = ...

local OT = addon.ObjectiveTracker

local Quests = {}
OT.Quests = Quests

local OWNER = "camelotObjectiveTrackerQuests"

--------------------------------------------------------------------------------
-- The quest object
--------------------------------------------------------------------------------
-- QuestMixin, with one change. Blizzard's Init registers a closure with
-- QuestEventListener to fill title, requiredMoney, isRepeatable and
-- isLegendary when the quest's data arrives; that listener calls its
-- callbacks in a plain loop, so an addon's closure in the list taints every
-- callback after it for the same quest. Here the four are read at Init when
-- the client has the data, and on QUEST_DATA_LOAD_RESULT when it does not.

local QuestMixin = {}
QuestMixin.__index = QuestMixin

local objects = {}    -- questID -> quest object
local awaiting = {}   -- questID -> true: the four fields wait on the quest's data
local questModules = {}

local function readLoadedFields(quest)
    local questID = quest.questID
    quest.title = QuestUtils_GetQuestName(questID) or ""
    quest.requiredMoney = C_QuestLog.GetRequiredMoney(questID) or 0
    quest.isRepeatable = C_QuestLog.IsRepeatableQuest(questID)
    quest.isLegendary = C_QuestInfoSystem.GetQuestClassification(questID) == Enum.QuestClassification.Legendary
end

function QuestMixin:Init(questID)
    self.questID = questID
    self:CheckRefresh()

    self.title = ""
    self.requiredMoney = 0
    self.isRepeatable = false
    self.isLegendary = false

    if HaveQuestData(questID) then
        readLoadedFields(self)
    else
        awaiting[questID] = true
        C_QuestLog.RequestLoadQuestByID(questID)
    end
end

function QuestMixin:CheckRefresh()
    if self.hasQuestLogInfo then
        return
    end

    -- May not exist; without it the object carries minimal info.
    local questLogIndex = C_QuestLog.GetLogIndexForQuestID(self.questID)
    if questLogIndex then
        local questLogInfo = C_QuestLog.GetInfo(questLogIndex)
        if questLogInfo then
            self.hasQuestLogInfo = true

            for key, value in pairs(questLogInfo) do
                self[key] = value
            end

            -- The dynamic fields, which would go stale.
            self.questLogIndex = nil
            self.isOnMap = nil
            self.isCollapsed = nil
            self.hasLocalPOI = nil
        end
    end
end

function QuestMixin:GetID()
    return self.questID
end

function QuestMixin:GetQuestLogIndex()
    return C_QuestLog.GetLogIndexForQuestID(self:GetID())
end

function QuestMixin:IsComplete()
    return C_QuestLog.IsComplete(self:GetID())
end

function QuestMixin:IsDisabledForSession()
    return C_QuestLog.IsQuestDisabledForSession(self:GetID())
end

function QuestMixin:IsCampaign()
    return self:GetCampaignID() ~= 0
end

function QuestMixin:GetCampaignID()
    if self.campaignID == nil then
        self.campaignID = C_CampaignInfo.GetCampaignID(self:GetID())
    end
    return self.campaignID
end

function QuestMixin:IsCalling()
    if self.isCalling == nil then
        self.isCalling = self:GetQuestClassification() == Enum.QuestClassification.Calling
    end
    return self.isCalling
end

function QuestMixin:IsImportant()
    if self.isImportant == nil then
        self.isImportant = C_QuestLog.IsImportantQuest(self:GetID())
    end
    return self.isImportant
end

function QuestMixin:IsMeta()
    if self.isMeta == nil then
        self.isMeta = C_QuestLog.IsMetaQuest(self:GetID())
    end
    return self.isMeta
end

function QuestMixin:IsRepeatableQuest()
    return self.isRepeatable
end

function QuestMixin:IsLegendary()
    return self.isLegendary
end

function QuestMixin:IsOnMap()
    return C_QuestLog.IsOnMap(self:GetID())
end

function QuestMixin:GetQuestClassification()
    -- This can change at run time.
    return C_QuestInfoSystem.GetQuestClassification(self:GetID())
end

--- ObjectCache's Get over Camelot's table: the object for a quest, created on
--- the first ask and kept for the session.
function Quests.Get(questID)
    local quest = objects[questID]
    if quest then
        quest:CheckRefresh()
        return quest
    end

    quest = setmetatable({}, QuestMixin)
    quest:Init(questID)
    objects[questID] = quest
    return quest
end

local function onQuestData(_, questID, success)
    if not (success and awaiting[questID]) then return end
    awaiting[questID] = nil
    local quest = objects[questID]
    if not quest then return end
    readLoadedFields(quest)
    -- The header draws the title, and no client event is promised after this one.
    for _, module in ipairs(questModules) do
        module:MarkDirty()
    end
end

--------------------------------------------------------------------------------
-- The quest modules
--------------------------------------------------------------------------------
-- The three methods in which Blizzard's quest module asks QuestCache, as
-- instance methods on each Camelot quest module, reading Quests.Get.

local function compareQuestWatchInfos(info1, info2)
    local quest1, quest2 = info1.quest, info2.quest

    if quest1:IsCalling() ~= quest2:IsCalling() then
        return quest1:IsCalling()
    end

    if quest1.overridesSortOrder ~= quest2.overridesSortOrder then
        return quest1.overridesSortOrder
    end

    return info1.index < info2.index
end

local function buildQuestWatchInfos(self)
    local infos = {}

    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if questID then
            local quest = Quests.Get(questID)
            if self:ShouldDisplayQuest(quest) then
                table.insert(infos, { quest = quest, index = i })
            end
        end
    end

    table.sort(infos, compareQuestWatchInfos)
    return infos
end

local function shouldDisplayAutoQuest(self, questID)
    return not C_QuestLog.IsQuestBounty(questID) and self:ShouldDisplayQuest(Quests.Get(questID))
end

-- QuestObjectiveTrackerMixin:OnBlockHeaderClick with two changes, both for
-- the same reason. Blizzard's plain left click and its "Show on map" entry
-- call QuestMapFrame_OpenToQuestDetails, which shows the world map. A map
-- shown from addon code registers its quest provider's supertrack callback
-- as the addon, and the registry reads the old slot before each rewrite, so
-- the slot stays the addon's for the session and every later pin refresh is
-- tainted from its first line. Here the left click supertracks the quest, as
-- the POI button beside the header does, and the menu has no "Show on map".
--
-- `self` is the module, or a Current Objectives card standing in for one:
-- the method reads only GetContextMenuParent, RemoveAutoQuestPopUp and
-- restoreGamepadFocusOnMenuClose, and a card with `skipGamepadRestore` set
-- leaves the gamepad focus alone when the menu closes. A card also sets
-- `opensDetailsOnClick`: its left click opens the quest's details popup, the
-- menu's "View in quest log", which the popup's own Show closes again on a
-- second click.

-- The menu's "View in quest log": QuestLogPopupDetailFrame, never the map.
local function openDetails(self, questID)
    if InputUtil.IsGamepadUIEnabled() and GamepadHudMode:IsShown() then
        GamepadHudMode:Hide()
    end
    QuestUtil.OpenQuestDetails(questID)
    self.restoreGamepadFocusOnMenuClose = false
end

local function questClick(self, questID, mouseButton)
    if ChatFrameUtil.TryInsertQuestLinkForQuestID(questID) then
        return
    end

    if mouseButton ~= "RightButton" then
        if IsModifiedClick("QUESTWATCHTOGGLE") then
            if QuestUtil.CanRemoveQuestWatch() then
                C_QuestLog.RemoveQuestWatch(questID)
            end
        else
            local quest = Quests.Get(questID)
            if quest.isAutoComplete and quest:IsComplete() then
                self:RemoveAutoQuestPopUp(questID)
                ShowQuestComplete(questID)
            elseif self.opensDetailsOnClick then
                openDetails(self, questID)
            else
                C_SuperTrack.SetSuperTrackedQuestID(questID)
            end
        end
        return
    end

    local menu = MenuUtil.CreateContextMenu(self:GetContextMenuParent(), function(owner, rootDescription)
        rootDescription:SetTag("MENU_QUEST_OBJECTIVE_TRACKER")
        self.restoreGamepadFocusOnMenuClose = true

        rootDescription:CreateTitle(C_QuestLog.GetTitleForQuestID(questID))

        if C_SuperTrack.GetSuperTrackedQuestID() ~= questID then
            rootDescription:CreateButton(SUPER_TRACK_QUEST, function()
                C_SuperTrack.SetSuperTrackedQuestID(questID)
            end)
        else
            rootDescription:CreateButton(STOP_SUPER_TRACK_QUEST, function()
                C_SuperTrack.SetSuperTrackedQuestID(0)
            end)
        end

        local toggleDetailsText = QuestUtil.IsShowingQuestDetails(questID)
            and OBJECTIVES_HIDE_VIEW_IN_QUESTLOG or OBJECTIVES_VIEW_IN_QUESTLOG

        rootDescription:CreateButton(toggleDetailsText, function()
            openDetails(self, questID)
        end)

        if QuestUtil.CanRemoveQuestWatch() then
            rootDescription:CreateButton(OBJECTIVES_STOP_TRACKING, function()
                C_QuestLog.RemoveQuestWatch(questID)
            end)
        end

        if C_QuestLog.IsPushableQuest(questID) and IsInGroup() then
            rootDescription:CreateButton(SHARE_QUEST, function()
                QuestUtil.ShareQuest(questID)
            end)
        end

        if InputUtil.IsGamepadUIEnabled() then
            rootDescription:CreateButton(SHARE_IN_CHAT, function()
                local chatLink = GetQuestLink(questID)
                if not ChatFrameUtil.InsertLink(chatLink) then
                    ChatFrameUtil.OpenChat(chatLink)
                end
                self.restoreGamepadFocusOnMenuClose = false
            end)
        end

        rootDescription:CreateButton(ABANDON_QUEST_ABBREV, function()
            QuestMapQuestOptions_AbandonQuest(questID)
        end)
    end)

    if menu and InputUtil.IsGamepadUIEnabled() and not self.skipGamepadRestore then
        menu:SetClosedCallback(function()
            local owner = self:GetContextMenuParent()
            if owner ~= nil and not self.restoreGamepadFocusOnMenuClose then
                GamepadMode.FrameControlsManager:FrameHidden(owner)
            end
        end)
    end
end

local function onBlockHeaderClick(self, block, mouseButton)
    return questClick(self, block.id, mouseButton)
end

--- A click on a Current Objectives card, the way a quest header in the
--- tracker takes it. `host` is the card (see questClick).
function Quests.Click(host, questID, mouseButton)
    questClick(host, questID, mouseButton)
end

--- The auto-complete popup removal the quest modules own, for a card.
function Quests.RemoveAutoQuestPopUp(questID)
    local module = questModules[1]
    if module and module.RemoveAutoQuestPopUp then
        module:RemoveAutoQuestPopUp(questID)
    elseif type(_G.RemoveAutoQuestPopUp) == "function" then
        _G.RemoveAutoQuestPopUp(questID)
    end
end

--------------------------------------------------------------------------------
-- The POI buttons
--------------------------------------------------------------------------------
-- A block's POI button asks QuestCache for its quest's classification on
-- every style update (POIButtonMixin:GetQuestClassification), and Blizzard's
-- blocks take their buttons from a pool local to Blizzard's file, which
-- styles a new button before anything outside can reach it. So the Camelot
-- modules' blocks take theirs from the pool below, and each button answers
-- from the client, the value Blizzard's method returns through the cache.

local buttonsMade = 0
local blocksFitted = 0

local function poiGetQuestClassification(self)
    local questID = self:GetQuestID()
    if questID then
        return C_QuestInfoSystem.GetQuestClassification(questID)
    end
    return nil
end

local poiPool = addon.Pool.New(function()
    local button = CreateFrame("Button", nil, nil, "ObjectiveTrackerPOIButtonTemplate")
    button.GetQuestClassification = poiGetQuestClassification
    buttonsMade = buttonsMade + 1
    return button
end, function(button)
    button:Hide()
    button:ClearAllPoints()
end)

-- ObjectiveTrackerQuestPOIBlockMixin:GetPOIButton on Camelot's pool.
local function blockGetPOIButton(self, style)
    local button = self.poiButton
    if not button then
        button = poiPool:Acquire()
        button:SetParent(self)
        button:SetQuestID(self.poiQuestID)
        self.poiButton = button
        self:SetExtraAddAnimation(button.AddAnim)
    end

    button:SetStyle(style)
    button:SetSelected(self.poiIsSuperTracked)
    button:UpdateButtonStyle()
    button:Show()
    return button
end

-- ObjectiveTrackerQuestPOIBlockMixin:CheckAndReleasePOIButton on Camelot's pool.
local function blockCheckAndReleasePOIButton(self)
    if self.poiButton then
        poiPool:Release(self.poiButton)
        self.poiButton = nil
        self:SetExtraAddAnimation(nil)
        self:SetPOIInfo()
    end
end

-- GetBlock is where a module first holds a block, before any layout asks the
-- block for a button.
local function fitBlocks(module)
    local base = module.GetBlock
    module.GetBlock = function(self, id, optTemplate)
        local block, wasAlreadyActive = base(self, id, optTemplate)
        if block and block.GetPOIButton and block.GetPOIButton ~= blockGetPOIButton then
            block.GetPOIButton = blockGetPOIButton
            block.CheckAndReleasePOIButton = blockCheckAndReleasePOIButton
            blocksFitted = blocksFitted + 1
        end
        return block, wasAlreadyActive
    end
end

--------------------------------------------------------------------------------
-- Install
--------------------------------------------------------------------------------

local installed = false

--- Once, from the tracker's setup, before a module gets its container, so no
--- module runs a Blizzard method that asks QuestCache first. Blizzard's own
--- Scenario module rides the container as it is and is left alone.
function Quests.Install(modules)
    if installed then return end
    installed = true

    for _, module in ipairs(modules) do
        local name = module:GetName()
        if name and name:find("^Camelot") then
            if module.BuildQuestWatchInfos then
                module.BuildQuestWatchInfos = buildQuestWatchInfos
                module.ShouldDisplayAutoQuest = shouldDisplayAutoQuest
                module.OnBlockHeaderClick = onBlockHeaderClick
                questModules[#questModules + 1] = module
            end
            fitBlocks(module)
        end
    end

    addon.Events.On(OWNER, "QUEST_DATA_LOAD_RESULT", onQuestData)
end

--- Lines for /camelot tracker.
function Quests.Dump(push)
    local count, waiting = 0, 0
    for _ in pairs(objects) do count = count + 1 end
    for _ in pairs(awaiting) do waiting = waiting + 1 end
    push("quests: installed %s, quest modules %d, objects %d (%d awaiting data), "
        .. "POI buttons made %d (%d free), blocks fitted %d",
        tostring(installed), #questModules, count, waiting, buttonsMade, poiPool:FreeCount(), blocksFitted)
    push("")
end
