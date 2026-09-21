--------------------------------------------------------------------------------
-- forever/objectivetracker/mixins.lua
-- The three globals forever/objectivetracker/frames.xml names in its mixin=
-- attributes. They have to exist before the XML parses, so this file loads
-- first of the folder.
--
-- The tracker is Blizzard's own modular tracker running on Camelot-owned
-- frames: the container, every module, every block and line is Blizzard's
-- virtual template with Blizzard's mixin, instantiated under a Camelot name
-- (the tracker's doc). The container mixin here is
-- ObjectiveTrackerFrameMixin (Blizzard_ObjectiveTracker.lua, 12.1) copied,
-- plus the four things that mixin gets from templates ObjectiveTrackerFrame
-- inherits and this frame does not: RightManagedFrameTemplate and
-- EditModeObjectiveTrackerSystemTemplate.
--------------------------------------------------------------------------------

local addonName, addon = ...

--------------------------------------------------------------------------------
-- The container
--------------------------------------------------------------------------------

CamelotObjectiveTrackerMixin = {}

-- Kept off addon.Events: these are Blizzard's mixins transcribed, and their
-- events arrive through the XML frames' own OnEvent scripts, the contract the
-- templates and the manager hold them to.
function CamelotObjectiveTrackerMixin:OnLoad()
    ObjectiveTrackerContainerMixin.OnLoad(self)

    -- ObjectiveTrackerContainerMixin declares `modules = {}` in the mixin
    -- table itself, and CreateFromMixins copies the reference, so every
    -- container built from the template shares one module list. Blizzard has
    -- one container and never notices. With two, each AddModule on this frame
    -- landed in ObjectiveTrackerFrame's list as well, and Blizzard's parked
    -- frame then anchored the modules to itself on every update: the tracker
    -- at the top-left, gone whenever the parked frame had no rect, and a
    -- selection box with nothing under it (beta, 19 September 2026). Only
    -- RemoveAllModules ever replaces the table, which is why the Kiosk's
    -- second container calls it first. This list is this frame's own.
    self.modules = {}

    -- Blizzard's parked frame runs these too; SortQuestWatches and
    -- AddQuestWatch are idempotent, so both may. The Current Objectives pane
    -- is a third container from this mixin and leaves them to the main one.
    if not self.isCurrentPane then
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("ZONE_CHANGED")
        self:RegisterEvent("QUEST_ACCEPTED")
    end
end

function CamelotObjectiveTrackerMixin:OnEvent(event, ...)
    if event == "ZONE_CHANGED_NEW_AREA" then
        C_QuestLog.SortQuestWatches()
    elseif event == "ZONE_CHANGED" then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID ~= self.lastSortMapID then
            C_QuestLog.SortQuestWatches()
            self.lastSortMapID = mapID
        end
    elseif event == "QUEST_ACCEPTED" then
        local questID = ...
        if not C_QuestLog.IsQuestBounty(questID) and not C_QuestLog.IsQuestTask(questID) then
            if GetCVarBool("autoQuestWatch")
                and C_QuestLog.GetNumQuestWatches() < Constants.QuestWatchConsts.MAX_QUEST_WATCHES then
                C_QuestLog.AddQuestWatch(questID)
            end
        end
    end
end

function CamelotObjectiveTrackerMixin:ShouldShowHeader()
    if C_GameRules.IsGameRuleActive(Enum.GameRule.ObjectiveTrackerDisabled) then
        return false
    end
    return self:HasAnyModules()
end

-- The Current Objectives pane has no Header child: its one module's header is
-- its title, so every Header access below is guarded.
function CamelotObjectiveTrackerMixin:Update(dirtyUpdate)
    if not self:ShouldShowHeader() then
        if self.Header then self.Header:Hide() end
        return false
    end
    if self.Header then self.Header:Show() end

    local result = ObjectiveTrackerContainerMixin.Update(self, dirtyUpdate)

    -- The beta's container takes top padding providers off EventRegistry and
    -- moves the first module down by their sum in every update; the beta's
    -- frame mixin then moves the header down the same amount. Live has
    -- neither. Mirrored here so the header keeps its place above the modules
    -- on both.
    if self.topPaddingProviders and self.Header then
        local y = 0
        for provider in pairs(self.topPaddingProviders) do
            y = y - provider:GetTopPadding()
        end
        self.Header:SetPoint("TOPLEFT", self, "TOPLEFT", 0, y)
    end

    -- The quest item buttons ride the blocks by coordinate, so every layout
    -- re-places them (itembutton.lua). Read at call time: tracker.lua loads
    -- after the XML that runs this.
    local OT = addon.ObjectiveTracker
    if OT and OT.OnContainerUpdated then
        OT.OnContainerUpdated(self)
    end
    return result
end

-- ObjectiveTrackerContainerMixin:OnShow calls ManagedFrameMixin.OnShow, which
-- indexes self.layoutParent; this frame is not a managed frame and has none.
function CamelotObjectiveTrackerMixin:OnShow()
    self:UpdateHeight()
end

-- The stock SetCollapsed writes the state to self.Header unguarded; the
-- Current Objectives pane has no header, so its collapse is the state and
-- the update alone.
function CamelotObjectiveTrackerMixin:SetCollapsed(collapsed)
    if self.Header then
        ObjectiveTrackerContainerMixin.SetCollapsed(self, collapsed)
        return
    end
    self.isCollapsed = collapsed
    self:Update()
end

-- Read by the container's Update (skips ManageFramePositions) and UpdateHeight
-- (takes the custom-height branch, editModeHeight or 800). Blizzard's frame
-- answers it through EditModeSystemMixin; this frame is positioned by Camelot.
function CamelotObjectiveTrackerMixin:IsInDefaultPosition()
    return false
end

-- The manager writes its own background alpha, Blizzard's Edit Mode opacity
-- setting, to every container it holds: at AddContainer and on each layout
-- activation. Each container's background is a Camelot setting (style.lua),
-- so the manager's value is answered with the stored one for this container.
function CamelotObjectiveTrackerMixin:SetBackgroundAlpha(alpha)
    local Style = addon.ObjectiveTracker and addon.ObjectiveTracker.Style
    if Style then alpha = Style.BackgroundAlphaFor(self) end
    ObjectiveTrackerContainerMixin.SetBackgroundAlpha(self, alpha)
end

--------------------------------------------------------------------------------
-- The quest item slot
--------------------------------------------------------------------------------
-- What a block gets in place of Blizzard's item button: a plain 26x26 frame
-- that rides the stock right-edge path (AddRightEdgeFrame, GetRightEdgeFrame,
-- FreeUnusedRightEdgeFrames) and asks itembutton.lua for a secure button to
-- stand on it. The secure button itself is never a child of a block and is
-- never anchored to one: a protected frame parented to or anchored on a block
-- makes the block anchor-protected, and the tracker re-anchors blocks in
-- combat on every update.

CamelotQuestItemSlotMixin = {}

function CamelotQuestItemSlotMixin:SetUp(questLogIndex)
    self.questLogIndex = questLogIndex
    local OT = addon.ObjectiveTracker
    if OT and OT.Items then
        OT.Items.Bind(self, questLogIndex)
    end
end

-- Fires on release (the pool hides) and when an ancestor hides (a collapsed
-- module or tracker), both of which take the button off screen.
function CamelotQuestItemSlotMixin:OnHide()
    self.questLogIndex = nil
    local OT = addon.ObjectiveTracker
    if OT and OT.Items then
        OT.Items.Unbind(self)
    end
end

--------------------------------------------------------------------------------
-- The secure quest item button
--------------------------------------------------------------------------------
-- QuestObjectiveItemButtonMixin (Blizzard_ObjectiveTrackerShared.lua, 12.1)
-- with two changes. OnClick is gone: the button is a SecureActionButtonTemplate
-- whose type and item attributes use the item, because UseQuestLogSpecialItem
-- is protected. And questLogIndex and questID are plain fields rather than
-- attributes, because SetAttribute on a protected frame is blocked in combat
-- and the range check below runs every frame.

CamelotQuestItemButtonMixin = {}

function CamelotQuestItemButtonMixin:OnLoad()
    self:RegisterForClicks("AnyUp")
end

function CamelotQuestItemButtonMixin:OnEvent(event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        self.rangeTimer = -1
    elseif event == "BAG_UPDATE_COOLDOWN" then
        self:UpdateCooldown()
    elseif event == "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED" then
        local questID, inside = ...
        self:UpdateInsideBlob(questID, inside)
    end
end

function CamelotQuestItemButtonMixin:OnUpdate(elapsed)
    local rangeTimer = self.rangeTimer
    if not rangeTimer then return end
    local questLogIndex = self.questLogIndex
    if not questLogIndex then return end

    rangeTimer = rangeTimer - elapsed
    if rangeTimer <= 0 then
        local _, _, charges = GetQuestLogSpecialItemInfo(questLogIndex)
        if not charges or charges ~= self.charges then
            -- Blizzard dirties QuestObjectiveTracker by name here; this button
            -- belongs to whichever Camelot module laid out its slot.
            if self.ownerModule then
                self.ownerModule:MarkDirty()
            end
            return
        end
        local count = self.HotKey
        local valid = IsQuestLogSpecialItemInRange(questLogIndex)
        if valid == 0 then
            count:Show()
            count:SetVertexColor(1.0, 0.1, 0.1)
        elseif valid == 1 then
            count:Show()
            count:SetVertexColor(0.6, 0.6, 0.6)
        else
            count:Hide()
        end
        rangeTimer = TOOLTIP_UPDATE_TIME
    end
    self.rangeTimer = rangeTimer
end

function CamelotQuestItemButtonMixin:OnShow()
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("BAG_UPDATE_COOLDOWN")
    self:RegisterEvent("PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED")
end

function CamelotQuestItemButtonMixin:OnHide()
    self:UnregisterEvent("PLAYER_TARGET_CHANGED")
    self:UnregisterEvent("BAG_UPDATE_COOLDOWN")
    self:UnregisterEvent("PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED")
end

function CamelotQuestItemButtonMixin:OnEnter()
    if not self.questLogIndex then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetQuestLogSpecialItem(self.questLogIndex)
end

--- The visual half of a bind. The attributes are set by itembutton.lua, out
--- of combat, before this runs.
function CamelotQuestItemButtonMixin:SetUp(questLogIndex)
    local _, item, charges = GetQuestLogSpecialItemInfo(questLogIndex)
    self.questLogIndex = questLogIndex
    self.questID = C_QuestLog.GetQuestIDForLogIndex(questLogIndex)
    self.charges = charges
    self.rangeTimer = -1
    SetItemButtonTexture(self, item)
    SetItemButtonCount(self, charges)
    self:UpdateCooldown()
    self:CheckUpdateInsideBlob()
end

function CamelotQuestItemButtonMixin:UpdateCooldown()
    local questLogIndex = self.questLogIndex
    if not questLogIndex then return end
    local start, duration, enable = GetQuestLogSpecialItemCooldown(questLogIndex)
    if start then
        CooldownFrame_Set(self.Cooldown, start, duration, enable)
        if duration > 0 and enable == 0 then
            SetItemButtonTextureVertexColor(self, 0.4, 0.4, 0.4)
        else
            SetItemButtonTextureVertexColor(self, 1, 1, 1)
        end
    end
end

function CamelotQuestItemButtonMixin:CheckUpdateInsideBlob()
    local questID = self.questID
    if not questID then return end
    self:UpdateInsideBlob(questID, C_Minimap.IsInsideQuestBlob(questID))
end

function CamelotQuestItemButtonMixin:UpdateInsideBlob(questID, inside)
    if questID == self.questID then
        self.GlowAnim.region = self.Glow
        if inside then
            self.GlowAnim:BeginPlaying()
        end
    end
end
