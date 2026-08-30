-- escapekey.lua - ESC-to-close wiring for addon popups, safe to build in combat
local addonName, addon = ...

addon.EscapeKey = addon.EscapeKey or {}
local EscapeKey = addon.EscapeKey

--------------------------------------------------------------------------------
-- Why this exists
--
-- SetPropagateKeyboardInput is protected: any call from addon code during
-- combat lockdown raises ADDON_ACTION_BLOCKED. Every popup in this addon is
-- built on first use, so the call that arms ESC handling runs whenever the
-- user first opens that menu, which is routinely mid-fight.
--
-- EnableKeyboard and the propagate call must move together. A frame with the
-- keyboard enabled but propagation left at its default swallows every key
-- while it is shown, so arming only the half that combat permits would eat
-- the player's keybinds. Arming is all-or-nothing, deferred to the first
-- moment out of combat.
--------------------------------------------------------------------------------

-- Frames attached while the arming was blocked. Weak-keyed: a popup that goes
-- away before combat ends should not be kept alive by this list.
local pending = setmetatable({}, { __mode = "k" })

local function arm(frame)
    if InCombatLockdown() then return false end
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    return true
end

-- Wires ESC on a popup: ESC runs onEscape and stops there, every other key
-- passes through to the game. Safe to call in combat; the keyboard trap arms
-- itself at the next opportunity (combat ending, or the frame being shown).
function EscapeKey.Attach(frame, onEscape)
    if not frame or type(onEscape) ~= "function" then return end

    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            -- In combat ESC also reaches whatever Blizzard has next in line
            -- (the game menu, usually). Closing the Scoot popup still happens.
            if not InCombatLockdown() then
                self:SetPropagateKeyboardInput(false)
            end
            onEscape(self)
            -- The flag persists on the frame, and a popup reopened in combat
            -- could not restore it there: without this the frame would sit
            -- non-propagating and eat the player's keys. The restore is
            -- deferred because doing it inline would undo the suppression of
            -- the very keypress being handled.
            C_Timer.After(0, function()
                if not InCombatLockdown() and self:IsKeyboardEnabled() then
                    self:SetPropagateKeyboardInput(true)
                end
            end)
        elseif not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- Every show re-arms: it catches a popup first built in combat, and it
    -- resets propagation to the open default, which is the one state a
    -- combat-blocked ESC could have left wrong.
    frame:HookScript("OnShow", function(self)
        if arm(self) then
            pending[self] = nil
        end
    end)

    if arm(frame) then
        pending[frame] = nil
    else
        pending[frame] = true
    end
end

addon.Events.On("EscapeKey", "PLAYER_REGEN_ENABLED", function()
    for frame in pairs(pending) do
        if arm(frame) then
            pending[frame] = nil
        end
    end
end)
