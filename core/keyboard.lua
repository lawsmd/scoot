-- keyboard.lua - Keyboard focus taken by Lua, for every edit box the addon owns
local addonName, addon = ...

addon.Keyboard = addon.Keyboard or {}
local Keyboard = addon.Keyboard

--------------------------------------------------------------------------------
-- Why this exists
--
-- A click on an edit box is the engine's own focus change. SetFocus from Lua
-- is the addon's, and the OnEditFocusLost of whatever frame held the focus
-- runs on the addon's path. Under the client's gamepad UI the chat edit box
-- keeps keyboard focus after a send (its ClearChat only empties the text
-- there), and its OnEditFocusLost hands the gamepad focus back through the
-- binding stack into SetPreferredGamepadInteractTarget, a protected function.
-- Taken from Lua, that focus change ends in ADDON_ACTION_FORBIDDEN with the
-- addon's name on it. So while a gamepad layout is in use, focus is taken only
-- when no other frame holds it; the player clicks the box instead, which is
-- the engine's change. On the mouse-and-keyboard client nothing changes.
--------------------------------------------------------------------------------

-- The frame holding keyboard focus, or nil.
function Keyboard.FocusHolder()
    if GetCurrentKeyBoardFocus then
        return GetCurrentKeyBoardFocus()
    end
    return nil
end

-- Gives editBox keyboard focus, unless a gamepad layout is in use and another
-- frame holds it. Returns whether the box has focus afterwards.
function Keyboard.TakeFocus(editBox)
    if not editBox then return false end
    local gamepad = addon.Gamepad and addon.Gamepad.IsActive and addon.Gamepad.IsActive()
    if gamepad then
        local holder = Keyboard.FocusHolder()
        if holder and holder ~= editBox then return false end
    end
    editBox:SetFocus()
    return true
end
