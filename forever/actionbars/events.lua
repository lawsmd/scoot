--------------------------------------------------------------------------------
-- forever/actionbars/events.lua
-- The event side of the Camelot action buttons. Blizzard's buttons register
-- themselves in three frames of Blizzard_ActionBar/Shared/ActionButton.lua:
-- ActionBarButtonEventsFrame (every button), ActionBarActionEventsFrame
-- (buttons holding an action) and ActionBarButtonUpdateFrame (buttons that
-- need a tick). The action bar controller loops the first of those from an
-- untainted context, and one Camelot entry taints every button after it,
-- ending in a protected Show on the main bar. So a Camelot button enters
-- none of them: this file transcribes the three lists and the dispatch
-- rules and forwards to the Camelot buttons through addon.Events.
--
-- Also the blocked-action log and the note log that /camelot actionbars
-- prints; the first fight is read from them.
--------------------------------------------------------------------------------

local addonName, addon = ...

local ActionBars = addon.ActionBars
local Events = {}
ActionBars.Events = Events

local OWNER = ActionBars.OWNER

--------------------------------------------------------------------------------
-- The lists
--------------------------------------------------------------------------------

-- ActionBarButtonEventsFrameMixin:OnLoad. The two pet unit events are
-- registered plain and filtered on the unit below.
local BUTTON_EVENTS = {
    "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS",
    "GAME_PAD_ACTIVE_CHANGED", "UPDATE_SHAPESHIFT_FORM", "ACTIONBAR_UPDATE_COOLDOWN",
    "PET_BAR_UPDATE", "PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_FLAGS", "UNIT_AURA",
}
local BUTTON_UNIT = { UNIT_FLAGS = "pet", UNIT_AURA = "pet" }

-- ActionBarActionEventsFrameMixin:OnLoad, minus its EventRegistry callback
-- for the assisted combat rotation: a Camelot callback in that dispatch
-- loop would taint it. The player unit events are registered plain and
-- filtered on the unit below.
local ACTION_EVENTS = {
    "SPELL_UPDATE_CHARGES", "UPDATE_INVENTORY_ALERTS", "TRADE_SKILL_SHOW",
    "TRADE_SKILL_CLOSE", "ARCHAEOLOGY_CLOSED", "PLAYER_ENTER_COMBAT",
    "PLAYER_LEAVE_COMBAT", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
    "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "COMPANION_UPDATE",
    "UNIT_INVENTORY_CHANGED", "UNIT_SPELLCAST_SENT",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_RETICLE_TARGET",
    "UNIT_SPELLCAST_RETICLE_CLEAR", "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "LEARNED_SPELL_IN_SKILL_LINE", "PET_STABLE_UPDATE", "PET_STABLE_SHOW",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
    "UPDATE_SUMMONPETS_ACTION", "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE",
    "SPELL_UPDATE_ICON",
}
local ACTION_UNIT = {
    UNIT_SPELLCAST_INTERRUPTED = "player", UNIT_SPELLCAST_SUCCEEDED = "player",
    UNIT_SPELLCAST_FAILED = "player", UNIT_SPELLCAST_START = "player",
    UNIT_SPELLCAST_STOP = "player", UNIT_SPELLCAST_CHANNEL_START = "player",
    UNIT_SPELLCAST_CHANNEL_STOP = "player", UNIT_SPELLCAST_RETICLE_TARGET = "player",
    UNIT_SPELLCAST_RETICLE_CLEAR = "player", UNIT_SPELLCAST_EMPOWER_START = "player",
    UNIT_SPELLCAST_EMPOWER_STOP = "player", LOSS_OF_CONTROL_ADDED = "player",
    LOSS_OF_CONTROL_UPDATE = "player",
}

-- ActionBarActionEventsFrameMixin:IsSpellcastEvent: these reach only the
-- button whose action is the spell being cast.
local SPELLCAST = {
    UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_RETICLE_TARGET = true, UNIT_SPELLCAST_RETICLE_CLEAR = true,
    UNIT_SPELLCAST_EMPOWER_START = true, UNIT_SPELLCAST_EMPOWER_STOP = true,
    UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_FAILED = true,
}

--------------------------------------------------------------------------------
-- Logs
--------------------------------------------------------------------------------

local RING_MAX = 40

local function ring(list, row)
    if #list >= RING_MAX then table.remove(list, 1) end
    list[#list + 1] = row
end

local blocked, blockedCount = {}, 0
local notes = {}

-- Every blocked or forbidden call naming this addon, with the lockdown
-- state: the first fight's verdict on a question is one of these rows or
-- their absence.
local function noteBlocked(event, name, func)
    if name ~= addonName then return end
    blockedCount = blockedCount + 1
    ring(blocked, string.format("%s %s %s%s", date("%H:%M:%S"), event, tostring(func),
        InCombatLockdown() and " (lockdown)" or ""))
end

--- A guarded call that failed, by tag. The mixins record a refused secret
--- read here rather than dropping the whole update.
function Events.Note(tag, message)
    ring(notes, string.format("%s %s: %s%s", date("%H:%M:%S"), tag, tostring(message),
        InCombatLockdown() and " (lockdown)" or ""))
end

function Events.BlockedRows()
    return blocked, blockedCount
end

function Events.NoteRows()
    return notes
end

--------------------------------------------------------------------------------
-- Forwarding
--------------------------------------------------------------------------------

local function eachButton()
    return ipairs(ActionBars.Buttons or {})
end

local function forwardButtonEvent(event, ...)
    local unit = BUTTON_UNIT[event]
    if unit and (...) ~= unit then return end
    for _, button in eachButton() do
        button:OnEvent(event, ...)
    end
end

-- ActionBarActionEventsFrameMixin:OnEvent's three rules, with the tooltip
-- owner read off the tooltip instead of a field on a Blizzard frame.
local function forwardActionEvent(event, ...)
    local unit = ACTION_UNIT[event]
    if unit and (...) ~= unit then return end

    if event == "UNIT_INVENTORY_CHANGED" then
        if (...) ~= "player" then return end
        local owner = GameTooltip:GetOwner()
        for _, button in eachButton() do
            if button.eventsRegistered and button == owner then
                button:SetTooltip()
            end
        end
        return
    end

    if SPELLCAST[event] then
        if (...) ~= "player" then return end
        local spellID
        if event == "UNIT_SPELLCAST_SENT" then
            spellID = select(4, ...)
        else
            spellID = select(3, ...)
        end
        for _, button in eachButton() do
            if button.eventsRegistered then
                -- The match compares the payload's spell id with the slot's,
                -- and the payload may be secret in a fight.
                local ok, matches = pcall(button.MatchesActiveButtonSpellID, button, spellID)
                if ok and matches then
                    button:OnEvent(event, ...)
                elseif not ok then
                    Events.Note("spellcast match", matches)
                end
            end
        end
        return
    end

    for _, button in eachButton() do
        if button.eventsRegistered then
            button:OnEvent(event, ...)
        end
    end
end

--------------------------------------------------------------------------------
-- The tick
--------------------------------------------------------------------------------
-- ActionBarButtonUpdateFrame: a button's CheckNeedsUpdate puts it here while
-- its state or flash is dirty, and the frame ticks only while any is.

local ticking = {}
local tickFrame = CreateFrame("Frame")
tickFrame:Hide()
tickFrame:SetScript("OnUpdate", function(_, elapsed)
    for button in pairs(ticking) do
        button:OnUpdate(elapsed)
    end
end)

function Events.SetTicking(button, on)
    ticking[button] = on and true or nil
    tickFrame:SetShown(next(ticking) ~= nil)
end

function Events.TickingCount()
    local n = 0
    for _ in pairs(ticking) do n = n + 1 end
    return n
end

--------------------------------------------------------------------------------
-- Install
--------------------------------------------------------------------------------

local installed = false

function Events.Install()
    if installed then return end
    installed = true
    for _, event in ipairs(BUTTON_EVENTS) do
        addon.Events.On(OWNER, event, forwardButtonEvent)
    end
    for _, event in ipairs(ACTION_EVENTS) do
        addon.Events.On(OWNER, event, forwardActionEvent)
    end
    addon.Events.On(OWNER, "ADDON_ACTION_BLOCKED", noteBlocked)
    addon.Events.On(OWNER, "ADDON_ACTION_FORBIDDEN", noteBlocked)
end

function Events.IsInstalled()
    return installed
end
