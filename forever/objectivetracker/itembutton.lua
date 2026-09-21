--------------------------------------------------------------------------------
-- forever/objectivetracker/itembutton.lua
-- The quest item buttons of Camelot's objective tracker.
--
-- Blizzard's block holds a plain button whose click calls
-- UseQuestLogSpecialItem, a protected function. Camelot's block holds a slot
-- (CamelotQuestItemSlotTemplate, no mouse) and a secure action button stands on
-- it from here: parented to a holder on UIParent, positioned by coordinate,
-- never a child of a block and never anchored to one, because a protected
-- frame in a block's tree makes the block anchor-protected and the tracker
-- re-anchors blocks in combat on every update.
--
-- A bind (attributes, art, scale, position, show) and a release both need the
-- button out of lockdown, so every change is a pass over all slots that runs
-- through addon.Events.RunOutOfCombat under one key. In combat a slot that
-- lost its quest fades its button to alpha 0 at once, which is allowed, and
-- the pass catches up on PLAYER_REGEN_ENABLED. That freeze is the one
-- divergence from Blizzard's tracker.
--------------------------------------------------------------------------------

local addonName, addon = ...

local OT = addon.ObjectiveTracker
local Items = {}
OT.Items = Items

local PASS_KEY = "camelotQuestItems"

-- Above the tracker's LOW strata. Anchored to UIParent's origin so a button's
-- offsets are screen coordinates in the button's own scale.
local holder = CreateFrame("Frame", "CamelotQuestItemButtons", UIParent)
holder:SetSize(1, 1)
holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
addon.Strata.ApplyHUD(holder, 10)

local slots = setmetatable({}, { __mode = "k" })   -- every slot ever set up
local buttonBySlot = {}                             -- slot -> button
local count = 0

local pool = addon.Pool.New(function()
    count = count + 1
    return CreateFrame("Button", "CamelotQuestItemButton" .. count, holder, "CamelotQuestItemButtonTemplate")
end, function(button)
    -- Out of combat only: the pass is the one caller.
    button:Hide()
    button:ClearAllPoints()
    button:SetAttribute("type", nil)
    button:SetAttribute("item", nil)
    button.questLogIndex = nil
    button.questID = nil
    button.ownerModule = nil
    button.slot = nil
    button:SetAlpha(1)
end)

--------------------------------------------------------------------------------
-- The pass
--------------------------------------------------------------------------------

local function ownerModuleOf(slot)
    -- AcquireFrame parents a right-edge frame to module.ContentsFrame.
    local contents = slot:GetParent()
    return contents and contents:GetParent() or nil
end

local function place(button, slot)
    -- Match the slot's effective scale so the button draws at the tracker's
    -- size, then its offsets from the holder's origin are the slot's own
    -- GetLeft and GetTop.
    local scale = slot:GetEffectiveScale() / holder:GetEffectiveScale()
    button:SetScale(scale)
    local left, top = slot:GetLeft(), slot:GetTop()
    if not (left and top) then return false end
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", left, top)
    return true
end

local function bindNow(slot)
    local questLogIndex = slot.questLogIndex
    local link = questLogIndex and GetQuestLogSpecialItemInfo(questLogIndex)
    local button = buttonBySlot[slot]

    if not (questLogIndex and link and slot:IsVisible()) then
        if button then
            buttonBySlot[slot] = nil
            pool:Release(button)
        end
        return
    end

    if not button then
        button = pool:Acquire()
        buttonBySlot[slot] = button
        button.slot = slot
    end
    button.ownerModule = ownerModuleOf(slot)
    button:SetAttribute("type", "item")
    button:SetAttribute("item", link)
    button:SetUp(questLogIndex)
    if place(button, slot) then
        button:SetAlpha(1)
        button:Show()
    else
        button:SetAlpha(0)
    end
end

local function runPass()
    for slot in pairs(slots) do
        bindNow(slot)
    end
end

local passQueued = false

-- One pass per frame at most, and only out of combat.
local function schedulePass()
    if passQueued then return end
    passQueued = true
    C_Timer.After(0, function()
        passQueued = false
        addon.Events.RunOutOfCombat(runPass, PASS_KEY)
    end)
end

--------------------------------------------------------------------------------
-- The slot's side
--------------------------------------------------------------------------------

--- From CamelotQuestItemSlotMixin:SetUp, inside a module's layout, before the
--- block is anchored. Records and waits for the container's update.
function Items.Bind(slot, questLogIndex)
    slots[slot] = true
    slot.questLogIndex = questLogIndex
    schedulePass()
end

--- From the slot's OnHide: released, or an ancestor hid.
function Items.Unbind(slot)
    local button = buttonBySlot[slot]
    if button then
        -- SetAlpha is not a protected method, so the button leaves the screen
        -- now; the release waits for the pass.
        button:SetAlpha(0)
    end
    schedulePass()
end

--- After every container layout (tracker.lua, OT.OnContainerUpdated) and
--- after an Edit Mode drop.
function Items.Reposition()
    schedulePass()
end

--------------------------------------------------------------------------------
-- /camelot tracker
--------------------------------------------------------------------------------

function Items.Dump(push)
    local n = 0
    for _ in pairs(buttonBySlot) do n = n + 1 end
    push("item buttons: %d bound, %d pooled, pass queued %s, in combat %s",
        n, pool:FreeCount(), tostring(passQueued), tostring(InCombatLockdown()))
    for slot, button in pairs(buttonBySlot) do
        local left, top = slot:GetLeft(), slot:GetTop()
        push("  %-26s quest log index %-3s item %-40s at %s, %s alpha %.1f shown %s",
            button:GetName(), tostring(button.questLogIndex),
            tostring(button:GetAttribute("item")),
            left and string.format("%.0f", left) or "?", top and string.format("%.0f", top) or "?",
            button:GetAlpha(), tostring(button:IsShown()))
    end
end
