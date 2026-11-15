--------------------------------------------------------------------------------
-- core/components/bags/picklock.lua
-- Pick Lock on a right-click. For a player who knows the spell, each locked
-- lockbox in the window gets a secure button over its cell: a right-click
-- casts Pick Lock with the box as the spell's item target, through the
-- SecureActionButton's target-bag and target-slot attributes. A left-click
-- passes through to the cell, so the box still picks up and drags.
--
-- The overlays sit on a holder parented to UIParent, never in the window: a
-- secure child would make the window protected, and the window has to open
-- and close in combat. A protected frame can only be placed, shown or hidden
-- out of combat, so the overlays are placed out of combat and the holder is
-- hidden as combat starts, before the lockdown. In combat a right-click on a
-- lockbox reaches Blizzard's cell and the game says the box is locked.
--
-- No API reports a locked box. The test is the LOCKED line in the item's
-- tooltip data, read only for Miscellaneous items.
--------------------------------------------------------------------------------

local _, addon = ...

local Bags = addon.Bags

local PickLock = {}
Bags.PickLock = PickLock

local SPELL_ID = 1804
local MISC_CLASS = (Enum.ItemClass and Enum.ItemClass.Miscellaneous) or 15

local holder
local pool
local active = {}
local lastClick     -- text, for the report

-- IsPlayerSpell is a deprecation fallback, defined only under the
-- loadDeprecationFallbacks CVar, so C_SpellBook is asked first.
local function Known()
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(SPELL_ID) and true or false
    end
    return IsPlayerSpell and IsPlayerSpell(SPELL_ID) or false
end

local function IsLockedBox(bag, slot, info)
    if not info or not info.itemID then return false end
    local classID = select(6, C_Item.GetItemInfoInstant(info.itemID))
    if classID ~= MISC_CLASS then return false end
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return false end
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    local lines = data and data.lines
    if not lines then return false end
    for _, line in ipairs(lines) do
        if line.leftText == LOCKED then return true end
    end
    return false
end

local function CreateOverlay()
    local b = CreateFrame("Button", nil, holder, "SecureActionButtonTemplate")
    b:RegisterForClicks("RightButtonUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type2", "spell")
    b:SetAttribute("spell2", SPELL_ID)
    -- pcall: on a client that restricts the call, the overlay keeps the left
    -- click and the box cannot be picked up while it is locked.
    pcall(b.SetPassThroughButtons, b, "LeftButton")
    -- The box may have been picked since the overlay was placed, and the scan
    -- that removes the overlay may not have run yet. Before Blizzard's handler
    -- reads the attributes, the click is set to cast on a box still locked
    -- and to use the item otherwise, which opens a picked box.
    b:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        local bag, slot = self:GetAttribute("target-bag"), self:GetAttribute("target-slot")
        if not (bag and slot) then return end
        local info = C_Container.GetContainerItemInfo(bag, slot)
        local want = IsLockedBox(bag, slot, info) and "spell" or "item"
        if self:GetAttribute("type2") ~= want then self:SetAttribute("type2", want) end
    end)
    -- For the report: the last click an overlay took, and whether the spell
    -- was waiting for a target after Blizzard's handler ran.
    b:HookScript("OnClick", function(self, button, down)
        lastClick = string.format("%s down=%s on bag %s slot %s, spell targeting after: %s",
            tostring(button), tostring(down),
            tostring(self:GetAttribute("target-bag")), tostring(self:GetAttribute("target-slot")),
            tostring(_G.SpellIsTargeting and _G.SpellIsTargeting()))
    end)
    b:SetScript("OnEnter", function(self)
        local cell = self.cell
        if not cell then return end
        local onEnter = cell:GetScript("OnEnter")
        if onEnter then onEnter(cell) end
        if Bags.Delete then Bags.Delete.Attach(cell, self) end
    end)
    b:SetScript("OnLeave", function(self)
        local cell = self.cell
        if cell then
            local onLeave = cell:GetScript("OnLeave")
            if onLeave then onLeave(cell) end
        end
        if Bags.Delete then Bags.Delete.MaybeHide() end
    end)
    return b
end

local function ResetOverlay(b)
    b.cell = nil
    b:ClearAllPoints()
    b:Hide()
end

local function EnsureHolder()
    if holder then return end
    holder = CreateFrame("Frame", addon.Brand .. "BagPickLock", UIParent)
    holder:SetAllPoints(UIParent)
    -- One strata over the window. The window is toplevel, and the client
    -- orders a toplevel window and its children as one group against the other
    -- frames of its strata, whatever their levels: measured on 15 November, an
    -- overlay at level 12 in the window's strata lost the mouse to its cell at
    -- level 10.
    holder:SetFrameStrata("HIGH")
    holder:Hide()
    pool = addon.Pool.New(CreateOverlay, ResetOverlay)
end

local function ReleaseAll()
    for i = #active, 1, -1 do
        pool:Release(active[i])
        active[i] = nil
    end
end

--- Out of combat only: one overlay per locked box, the holder shown with the
--- window.
local function Place()
    if InCombatLockdown() then return end
    EnsureHolder()
    ReleaseAll()
    local window = Bags.Window.Frame()
    if not (window and window:IsShown() and Known()) then
        holder:Hide()
        return
    end
    Bags.Cells.Each(function(cell, bag, slot)
        if Bags.IsKeyring(bag) then return end
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if IsLockedBox(bag, slot, info) then
            local b = pool:Acquire()
            b.cell = cell
            b:SetAttribute("target-bag", bag)
            b:SetAttribute("target-slot", slot)
            b:SetAttribute("type2", "spell")
            b:SetAttribute("item2", bag .. " " .. slot)
            b:SetAllPoints(cell)
            b:Show()
            active[#active + 1] = b
        end
    end)
    holder:SetShown(#active > 0)
end

function PickLock.Queue()
    if not Bags.component then return end
    Bags.component:RunOutOfCombat(Place, "pickLock")
end

--- The window closed. In combat the holder is already hidden.
function PickLock.HideAll()
    if not holder or InCombatLockdown() then return end
    ReleaseAll()
    holder:Hide()
end

-- PLAYER_REGEN_DISABLED fires before the lockdown starts, the last moment a
-- protected frame can be hidden. The overlays are released too: an overlay
-- anchored to a cell, even hidden, bars the cell from moving in combat, and a
-- loot refresh in combat places the cells again.
addon.Events.On("Bags.pickLock", "PLAYER_REGEN_DISABLED", function()
    if not holder then return end
    ReleaseAll()
    holder:Hide()
end)
addon.Events.On("Bags.pickLock", "PLAYER_REGEN_ENABLED", function()
    if Bags.active then PickLock.Queue() end
end)
addon.Events.On("Bags.pickLock", "SPELLS_CHANGED", function()
    if Bags.active then PickLock.Queue() end
end)

-- A finished Pick Lock: scan again so the picked box loses its overlay. Twice
-- more after it, in case the item's tooltip data trails the cast.
addon.Events.On("Bags.pickLock", "UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
    if unit ~= "player" or not Bags.active then return end
    if type(spellID) ~= "number" or issecretvalue(spellID) or spellID ~= SPELL_ID then return end
    PickLock.Queue()
    C_Timer.After(0.3, PickLock.Queue)
    C_Timer.After(1, PickLock.Queue)
end)

--------------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------------

local function Report()
    if not addon.DebugLines then return end
    local lines, push = addon.DebugLines("=== Bags: Pick Lock ===", "")
    local book = C_SpellBook
    push("build: %s", tostring((select(1, GetBuildInfo()))))
    push("in combat: %s", tostring(InCombatLockdown()))
    push("C_SpellBook.IsSpellKnown(%d): %s", SPELL_ID,
        tostring(book and book.IsSpellKnown and book.IsSpellKnown(SPELL_ID)))
    push("IsPlayerSpell: %s", IsPlayerSpell and tostring(IsPlayerSpell(SPELL_ID)) or "not defined")
    push("spell name: %s", tostring(C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(SPELL_ID)))
    push("Known(): %s", tostring(Known()))
    push("LOCKED: %q", tostring(LOCKED))
    push("C_TooltipInfo.GetBagItem: %s", tostring(C_TooltipInfo ~= nil and C_TooltipInfo.GetBagItem ~= nil))
    push("feature running: %s, adopted (gamepad): %s", tostring(Bags.active or false), tostring(Bags.adopted or false))

    local window = Bags.Window.IsBuilt() and Bags.Window.Frame()
    if window then
        push("window: shown %s, strata %s, level %d, protected %s", tostring(window:IsShown()),
            window:GetFrameStrata(), window:GetFrameLevel(), tostring((window:IsProtected())))
    else
        push("window: not built")
    end
    if holder then
        push("holder: shown %s, visible %s, strata %s, level %d", tostring(holder:IsShown()),
            tostring(holder:IsVisible()), holder:GetFrameStrata(), holder:GetFrameLevel())
    else
        push("holder: not built (Place never ran)")
    end

    push("")
    push("Items whose tooltip has a line holding the LOCKED text:")
    local found = 0
    local needle = type(LOCKED) == "string" and LOCKED:lower() or "locked"
    Bags.Cells.Each(function(_, bag, slot)
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not (info and info.itemID and C_TooltipInfo and C_TooltipInfo.GetBagItem) then return end
        local data = C_TooltipInfo.GetBagItem(bag, slot)
        for i, line in ipairs(data and data.lines or {}) do
            local text = line.leftText
            if type(text) == "string" and text:lower():find(needle, 1, true) then
                found = found + 1
                local classID, subID = select(6, C_Item.GetItemInfoInstant(info.itemID))
                push("  bag %d slot %d item %d class %s/%s: line %d %q (type %s) -> IsLockedBox %s",
                    bag, slot, info.itemID, tostring(classID), tostring(subID), i, text,
                    tostring(line.type), tostring(IsLockedBox(bag, slot, info)))
            end
        end
    end)
    if found == 0 then push("  none") end

    push("")
    push("Overlays placed: %d", #active)
    for _, b in ipairs(active) do
        local cell = b.cell
        push("  bag %s slot %s: shown %s, visible %s, strata %s, level %d, mouse %s, %dx%d, type2 %s spell2 %s",
            tostring(b:GetAttribute("target-bag")), tostring(b:GetAttribute("target-slot")),
            tostring(b:IsShown()), tostring(b:IsVisible()), b:GetFrameStrata(), b:GetFrameLevel(),
            tostring(b:IsMouseEnabled()), b:GetWidth() or 0, b:GetHeight() or 0,
            tostring(b:GetAttribute("type2")), tostring(b:GetAttribute("spell2")))
        if cell then
            push("    its cell %s: strata %s, level %d, visible %s", cell:GetName() or "?",
                cell:GetFrameStrata(), cell:GetFrameLevel(), tostring(cell:IsVisible()))
        end
    end

    push("")
    push("Under the mouse now:")
    for _, f in ipairs(GetMouseFoci and GetMouseFoci() or {}) do
        local isOverlay = false
        for _, b in ipairs(active) do
            if b == f then isOverlay = true end
        end
        push("  %s%s", f.GetDebugName and f:GetDebugName() or tostring(f), isOverlay and " (an overlay)" or "")
    end
    push("")
    push("Last click an overlay took: %s", lastClick or "none")
    addon.DebugShowWindow("Bags: Pick Lock", lines)
end

addon:RegisterDebugCommand({
    name = "picklock",
    help = "Bags: why a right-click on a lockbox does or does not cast Pick Lock",
    handler = Report,
})
