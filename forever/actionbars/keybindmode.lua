--------------------------------------------------------------------------------
-- forever/actionbars/keybindmode.lua
-- Keybind Mode: hover an action button, press a key, and the key is bound.
--
-- Blizzard's Quick Keybind frame does this for Blizzard's buttons. Camelot
-- stays off it: the frame is protected, a Show from addon code runs its OnShow
-- tainted over MainActionBar and the multibars, its highlight pass names only
-- Blizzard's buttons, and closing it opens Blizzard's settings panel.
--
-- One catcher frame moves over the hovered button. It covers the secure
-- button, so a click binds and cannot cast. The binding writes are in
-- core/keybinds.lua; the keys are saved once, when the player leaves.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local Keybinds = addon.Keybinds

local Mode = {}
Keybinds.Mode = Mode

local OWNER = "CamelotActionBars.KeybindMode"
local NAV_KEY = "qolKeybinds"

-- Below the window at the DIALOG default of 100, and the catcher above it.
local HIGHLIGHT_LEVEL = 50
local CATCHER_LEVEL = 500
local HIGHLIGHT_ALPHA = 0.25
local HOVER_ALPHA = 0.55
-- A bar can show or hide during the mode, on a page change or a new pet.
local HIGHLIGHT_TICK = 0.2

local NEEDS_MOUSE = "Keybind Mode needs a mouse to hover the buttons."
local NEEDS_BARS = "Keybind Mode works on Camelot's action bars, and they are off."
local CLOSE_EDIT_MODE = "Close Edit Mode first."
local INSTRUCTIONS = "Hover a button and press a key to bind it. Escape on a button clears its key."
    .. " The middle and side mouse buttons and the wheel can be bound too."

local active = false
local dirty = false
local installed = false
local targets = {}
local commandOf = {}
local catcher, window, statusText, highlights, ticker
-- The window's height without the status line, and one line of that status.
local windowBase, statusLine = 0, 0

local function accentTexture(frame, alpha)
    local r, g, b = addon.UI.Theme:GetAccentColor()
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(frame)
    texture:SetColorTexture(r, g, b, alpha)
end

-- The window closes around the status, which holds one line even when empty.
local function setStatus(text)
    if not statusText then return end
    statusText:SetText(text or "")
    window:SetHeight(windowBase + math.max(statusLine, statusText:GetStringHeight() or 0))
end

local function bindingName(command)
    return GetBindingName(command) or command
end

--------------------------------------------------------------------------------
-- The bars
--------------------------------------------------------------------------------

-- The calls Edit Mode makes, and a grid on every bar so an empty slot can be
-- hovered.
local function showBars()
    local reason = ActionBars.Compact.REASON_EDITMODE
    for _, bar in pairs(ActionBars.Frames) do
        bar:SetShowGrid(true, reason)
    end
    ActionBars.Visibility.OnEditMode(true)
    ActionBars.Stance.OnEditMode(true)
end

local function restoreBars()
    ActionBars.Compact.OnEditMode(false)
    ActionBars.Visibility.OnEditMode(false)
    ActionBars.Stance.OnEditMode(false)
end

local function createHighlight()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(HIGHLIGHT_LEVEL)
    accentTexture(frame, HIGHLIGHT_ALPHA)
    frame:Hide()
    return frame
end

-- A button shown at alpha 0 is a gap a form can fill (compact.lua); no
-- highlight on it.
local function paintHighlights()
    for i, button in ipairs(targets) do
        highlights:Get(i):SetShown(button:IsVisible() and button:GetAlpha() > 0)
    end
end

local function placeHighlights()
    highlights = highlights or addon.Pool.NewIndexed(createHighlight)
    for i, button in ipairs(targets) do
        local frame = highlights:Get(i)
        frame:ClearAllPoints()
        frame:SetAllPoints(button)
    end
    paintHighlights()
    ticker = C_Timer.NewTicker(HIGHLIGHT_TICK, paintHighlights)
end

local function clearHighlights()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if highlights then highlights:HideFrom(1) end
end

--------------------------------------------------------------------------------
-- The catcher
--------------------------------------------------------------------------------

local function paintTooltip()
    local command = catcher.command
    if not command then return end
    GameTooltip:SetOwner(catcher, "ANCHOR_TOP")
    GameTooltip:SetText(bindingName(command), 1, 1, 1)
    local key = Keybinds.KeysOf(command)
    if key then
        GameTooltip:AddLine(GetBindingText(key), addon.UI.Theme:GetAccentColor())
        GameTooltip:AddLine(ESCAPE_TO_UNBIND, 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine(NOT_BOUND, 1, 0.3, 0.3)
        GameTooltip:AddLine(PRESS_KEY_TO_BIND, 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

local function clearKey(command)
    if not Keybinds.ClearPrimary(command) then return end
    dirty = true
    setStatus(bindingName(command) .. " unbound.")
end

local function bindKey(command, chord)
    local bound, movedFrom = Keybinds.BindPrimary(command, chord)
    if not bound then
        setStatus(GetBindingText(chord) .. " cannot be bound.")
        return
    end
    dirty = true
    local text = GetBindingText(chord) .. " bound to " .. bindingName(command) .. "."
    if movedFrom then text = text .. " Taken from " .. bindingName(movedFrom) .. "." end
    setStatus(text)
end

local function press(input)
    local command = catcher.command
    if not active or not command or InCombatLockdown() then return end
    if input == "ESCAPE" then
        clearKey(command)
    else
        local chord = Keybinds.ChordFor(input)
        if not chord then return end
        bindKey(command, chord)
    end
    paintTooltip()
end

local function dropCatcher()
    if not catcher then return end
    catcher.command = nil
    catcher:Hide()
    if GameTooltip:GetOwner() == catcher then GameTooltip:Hide() end
end

local function buildCatcher()
    if catcher then return end
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:SetFrameLevel(CATCHER_LEVEL)
    catcher:EnableMouse(true)
    catcher:EnableMouseWheel(true)
    catcher:EnableKeyboard(true)
    catcher:RegisterForClicks("AnyUp")
    accentTexture(catcher, HOVER_ALPHA)
    catcher:Hide()

    -- The tooltip waits for the catcher's own OnEnter: the button under it
    -- hides the tooltip in its OnLeave, which runs first.
    catcher:SetScript("OnEnter", paintTooltip)
    catcher:SetScript("OnLeave", dropCatcher)
    catcher:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local screenshot = GetBindingFromClick(key) == "SCREENSHOT"
        self:SetPropagateKeyboardInput(screenshot)
        if not screenshot then press(key) end
    end)
    catcher:SetScript("OnClick", function(_, mouseButton)
        if mouseButton ~= "LeftButton" and mouseButton ~= "RightButton" then press(mouseButton) end
    end)
    catcher:SetScript("OnMouseWheel", function(_, delta)
        press(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
    end)
end

local function onButtonEnter(button)
    if not active or InCombatLockdown() then return end
    catcher.command = commandOf[button]
    catcher:ClearAllPoints()
    catcher:SetAllPoints(button)
    catcher:Show()
end

--------------------------------------------------------------------------------
-- Leaving
--------------------------------------------------------------------------------

-- how: "save" and "revert" are the player's and reopen the page. "combat"
-- keeps the keys and saves at regen, and the page stays closed. "editmode"
-- leaves the bars as Edit Mode has just set them.
local function finish(how)
    if not active then return end
    active = false
    dropCatcher()
    clearHighlights()
    if window then window:Hide() end
    if how ~= "editmode" then restoreBars() end
    if dirty then
        if how == "revert" then
            Keybinds.RevertCurrent()
        else
            addon.Events.RunOutOfCombat(Keybinds.SaveCurrent, OWNER .. ".save")
        end
    end
    dirty = false
    if how == "save" or how == "revert" then addon.UI:OpenToPage(NAV_KEY) end
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function buildWindow()
    if window then return end
    local Controls = addon.UI.Controls
    local Theme = addon.UI.Theme
    local metrics = Controls.Metrics()
    local m = metrics.dialog
    local edge = metrics.windowInset or 0
    local pad = m.contentPadding + edge
    local textWidth = m.width - m.contentPadding * 2
    local buttonHeight = metrics.button.height
    local save = function() finish("save") end

    -- The modal dialog's surface and numbers, without its screen-wide wash:
    -- the player has to reach the bars. A width set on each string, never
    -- anchors, lets GetStringHeight answer for the wrapped text at once.
    window = addon.UI.WindowShell.Create({
        name = addon.Brand .. "KeybindModeWindow",
        role = "dialog",
        template = true,
        width = m.width + edge * 2,
        height = m.textTop + m.contentPadding + edge * 2,
        titleHeight = m.textTop,
        positionKey = "keybindModeWindow",
        onClose = save,
        escape = "capture",
        onEscape = save,
    })
    Controls.AddDialogTitle(window, "Keybind Mode", edge)

    local text = window:CreateFontString(nil, "ARTWORK")
    Theme:ApplyFont(text, "value", m.textFontSize)
    text:SetWidth(textWidth)
    text:SetPoint("TOP", window, "TOP", 0, -(m.textTop + edge))
    text:SetJustifyH("CENTER")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    text:SetTextColor(1, 1, 1, 1)
    text:SetText(INSTRUCTIONS)

    statusText = window:CreateFontString(nil, "ARTWORK")
    Theme:ApplyFont(statusText, "desc")
    statusText:SetWidth(textWidth)
    statusText:SetPoint("TOP", text, "BOTTOM", 0, -m.controlGap)
    statusText:SetJustifyH("CENTER")
    statusText:SetJustifyV("TOP")
    statusText:SetWordWrap(true)
    statusText:SetText("A")
    statusLine = statusText:GetStringHeight() or 0

    windowBase = m.textTop + (text:GetStringHeight() or 0) + m.controlGap
        + m.buttonTop + buttonHeight + m.contentPadding + edge * 2

    local done = Controls:CreateButton({
        parent = window, text = "Done", width = m.buttonMinWidth, height = buttonHeight, onClick = save,
    })
    local cancel = Controls:CreateButton({
        parent = window, text = "Cancel", width = m.buttonMinWidth, height = buttonHeight,
        onClick = function() finish("revert") end,
    })
    done:SetPoint("BOTTOMLEFT", window, "BOTTOM", -(m.buttonMinWidth * 2 + m.buttonGap) / 2, pad)
    cancel:SetPoint("BOTTOMLEFT", done, "BOTTOMRIGHT", m.buttonGap, 0)
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

--- Why the page's button is off, or nil when it can be used.
function Mode.DisabledReason()
    if addon.Gamepad and addon.Gamepad.IsActive() then return NEEDS_MOUSE end
    if not ActionBars.IsBuilt() then return NEEDS_BARS end
    return nil
end

--- Returns true, or nil and a message.
function Mode.Enter()
    if InCombatLockdown() then return nil, Keybinds.COMBAT_MESSAGE end
    if active then return true end
    local reason = Mode.DisabledReason()
    if reason then return nil, reason end
    if addon.EditMode.IsEditModeActiveOrOpening() then return nil, CLOSE_EDIT_MODE end

    active = true
    dirty = false
    buildCatcher()
    buildWindow()
    addon.UI.SettingsPanel:Hide()
    showBars()
    placeHighlights()
    setStatus("")
    window:Show()
    return true
end

--- Called once, at the end of the action bars' build.
function Mode.Install()
    if installed then return end
    installed = true

    local function add(button, command)
        if not button or not command then return end
        targets[#targets + 1] = button
        commandOf[button] = command
        button:HookScript("OnEnter", onButtonEnter)
    end

    for _, button in ipairs(ActionBars.Buttons) do
        add(button, button.commandName)
    end
    for i, button in ipairs(ActionBars.Stance.Buttons) do
        add(button, "SHAPESHIFTBUTTON" .. i)
    end
    if PetActionBar and PetActionBar.actionButtons then
        for i, button in ipairs(PetActionBar.actionButtons) do
            add(button, "BONUSACTIONBUTTON" .. i)
        end
    end

    addon.EditMode.OnEditMode(OWNER, {
        enter = function() finish("editmode") end,
        exit = function() end,
    })
    addon.Events.On(OWNER, "PLAYER_REGEN_DISABLED", function() finish("combat") end)
end
