-- GameMenu.lua - Custom Scoot-styled game menu (ESC menu replacement)
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.GameMenu = {}
local GameMenu = addon.UI.GameMenu

local Theme = addon.UI.Theme
local Window = addon.UI.Window
local Controls = addon.UI.Controls

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MENU_WIDTH = 290
local BUTTON_WIDTH = 240
local BUTTON_HEIGHT = 32
local SCOOT_BUTTON_HEIGHT = 36
local BUTTON_SPACING = 4
local SECTION_BREAK = 16
local HEADER_HEIGHT = 40
local PADDING_BOTTOM = 16

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local frame = nil       -- The menu frame
local buttons = {}      -- Created button references (for cleanup)
local initialized = false
local hookInstalled = false
local blizzMenuAlphaHidden = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function IsSettingEnabled()
    return addon.db and addon.db.profile and addon.db.profile.misc
        and addon.db.profile.misc.customGameMenu
end

local function RestoreBlizzardGameMenu()
    if not blizzMenuAlphaHidden then return end
    blizzMenuAlphaHidden = false
    GameMenuFrame:SetAlpha(1)
    GameMenuFrame:EnableMouse(true)
end

-- Wrap a callback in pcall for combat safety, play sound, and hide menu
local function MakeButtonAction(callback, sound)
    return function()
        pcall(PlaySound, sound or SOUNDKIT.IG_MAINMENU_OPTION)
        if frame then frame:Hide() end
        if callback then
            pcall(callback)
        end
    end
end

--------------------------------------------------------------------------------
-- Button Cleanup
--------------------------------------------------------------------------------

local function CleanupButtons()
    for _, btn in ipairs(buttons) do
        if btn then
            if btn.Cleanup then btn:Cleanup() end
            pcall(btn.Hide, btn)
            pcall(btn.SetParent, btn, nil)
        end
    end
    wipe(buttons)
end

--------------------------------------------------------------------------------
-- Scoot Button (inverted accent style)
--------------------------------------------------------------------------------

local function CreateScootButton(parent)
    local theme = Theme
    local ar, ag, ab = theme:GetAccentColor()

    local btn = Controls:CreateButton({
        parent = parent,
        text = "Scoot",
        width = BUTTON_WIDTH,
        height = SCOOT_BUTTON_HEIGHT,
        fontSize = 14,
        onClick = function()
            pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION)
            if frame then frame:Hide() end
            local UIPanel = addon.UI.SettingsPanel
            if UIPanel and UIPanel.Toggle then
                UIPanel:Toggle()
            end
        end,
    })

    -- Force inverted resting state: accent fill shown, dark text
    btn._hoverFill:Show()
    btn._label:SetTextColor(0, 0, 0, 1)

    -- Store the inverted flag so theme updates can maintain it
    btn._scootInverted = true

    -- Scanline sweep texture (2px tall white line for CRT refresh effect)
    local borderInset = btn._borderWidth or 2
    local scanline = btn:CreateTexture(nil, "ARTWORK")
    scanline:SetHeight(2)
    scanline:SetPoint("TOPLEFT", btn, "TOPLEFT", borderInset, -borderInset)
    scanline:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -borderInset, -borderInset)
    scanline:SetColorTexture(1, 1, 1, 0.6)
    scanline:Hide()
    btn._scanline = scanline
    btn._scanlineOffset = 0
    btn._scanlineAnimating = false

    -- Hover: show scanline sweep, fill stays, text stays black
    btn:SetScript("OnEnter", function(self)
        self._scanline:Show()
        self._scanlineOffset = 0
        self._scanlineAnimating = true
    end)

    btn:SetScript("OnLeave", function(self)
        self._scanline:Hide()
        self._scanlineAnimating = false
    end)

    btn:SetScript("OnUpdate", function(self, elapsed)
        if not self._scanlineAnimating then return end
        local inset = self._borderWidth or 2
        local innerH = self:GetHeight() - (2 * inset)
        self._scanlineOffset = self._scanlineOffset + (elapsed / 0.4) * innerH
        if self._scanlineOffset >= innerH then
            self._scanlineOffset = 0
        end
        self._scanline:SetPoint("TOPLEFT", self, "TOPLEFT", inset, -(inset + self._scanlineOffset))
        self._scanline:SetPoint("TOPRIGHT", self, "TOPRIGHT", -inset, -(inset + self._scanlineOffset))
    end)

    -- Override theme subscription to maintain inverted state
    if btn._subscribeKey then
        theme:Unsubscribe(btn._subscribeKey)
    end
    local subscribeKey = "GameMenu_ScootBtn_" .. tostring(btn)
    btn._subscribeKey = subscribeKey
    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Update border
        if btn._border then
            for _, tex in pairs(btn._border) do
                tex:SetColorTexture(r, g, b, 1)
            end
        end
        -- Maintain inverted fill (always shown)
        if btn._hoverFill then
            btn._hoverFill:SetColorTexture(r, g, b, 1)
            btn._hoverFill:Show()
        end
        -- Text stays black in all states
        btn._label:SetTextColor(0, 0, 0, 1)
    end)

    return btn
end

--------------------------------------------------------------------------------
-- Build Menu Buttons
--------------------------------------------------------------------------------

local function BuildButtons()
    if not frame then return end
    CleanupButtons()

    local yOffset = -HEADER_HEIGHT
    local btnIndex = 0

    local function AddButton(btn)
        if not btn then return end
        btnIndex = btnIndex + 1
        btn:ClearAllPoints()
        btn:SetPoint("TOP", frame, "TOP", 0, yOffset)
        btn:Show()
        buttons[btnIndex] = btn
        yOffset = yOffset - btn:GetHeight() - BUTTON_SPACING
    end

    local function AddSectionBreak()
        yOffset = yOffset - SECTION_BREAK
    end

    -- 1. Scoot (inverted accent button)
    AddButton(CreateScootButton(frame))

    AddSectionBreak()

    -- 2. Options (Blizzard Settings)
    AddButton(Controls:CreateButton({
        parent = frame,
        text = "Options",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = MakeButtonAction(function()
            if SettingsPanel and SettingsPanel.Open then
                SettingsPanel:Open()
            end
        end),
    }))

    -- 3. Store (conditional) - uses SecureActionButtonTemplate to click StoreMicroButton
    -- in a secure context, avoiding ADDON_ACTION_FORBIDDEN on EventStoreUISetShown()
    if C_StorePublic and C_StorePublic.IsEnabled and C_StorePublic.IsEnabled() and StoreMicroButton then
        AddButton(Controls:CreateButton({
            parent = frame,
            text = "Store",
            width = BUTTON_WIDTH,
            height = BUTTON_HEIGHT,
            secureAction = { type = "click", clickbutton = StoreMicroButton },
            onClick = function()
                pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION)
                if frame then frame:Hide() end
            end,
        }))
    end

    -- 4. Show Rewards (conditional - active storefront)
    if GameRulesUtil and GameRulesUtil.GetActiveAccountStore then
        local storeFrontID = GameRulesUtil.GetActiveAccountStore()
        if storeFrontID then
            AddButton(Controls:CreateButton({
                parent = frame,
                text = "Show Rewards",
                width = BUTTON_WIDTH,
                height = BUTTON_HEIGHT,
                onClick = MakeButtonAction(function()
                    if C_AddOns and C_AddOns.LoadAddOn then
                        pcall(C_AddOns.LoadAddOn, "Blizzard_AccountStore")
                    end
                    if AccountStoreFrame and AccountStoreFrame.SetStoreFrontID then
                        AccountStoreFrame:SetStoreFrontID(storeFrontID)
                    end
                    if AccountStoreUtil and AccountStoreUtil.SetAccountStoreShown then
                        AccountStoreUtil.SetAccountStoreShown(true)
                    end
                end),
            }))
        end
    end

    -- 5. Add-ons (conditional)
    if GameRulesUtil and GameRulesUtil.ShouldShowAddOns and GameRulesUtil.ShouldShowAddOns() then
        AddButton(Controls:CreateButton({
            parent = frame,
            text = "Add-ons",
            width = BUTTON_WIDTH,
            height = BUTTON_HEIGHT,
            onClick = MakeButtonAction(function()
                ShowUIPanel(AddonList)
            end),
        }))
    end

    -- 6. What's New (conditional)
    if GameRulesUtil and GameRulesUtil.ShouldShowSplashScreen and GameRulesUtil.ShouldShowSplashScreen() then
        AddButton(Controls:CreateButton({
            parent = frame,
            text = "What's New",
            width = BUTTON_WIDTH,
            height = BUTTON_HEIGHT,
            onClick = MakeButtonAction(function()
                C_SplashScreen.RequestLatestSplashScreen(true)
            end),
        }))
    end

    -- 7. Edit Mode (conditional) - uses SecureHandlerClickTemplate to open Edit Mode
    -- in a secure (untainted) context, preventing secret value errors during EditModeFrameSetup
    if EditModeManagerFrame and EditModeManagerFrame.CanEnterEditMode and EditModeManagerFrame:CanEnterEditMode() then
        local editModeBtn = Controls:CreateButton({
            parent = frame,
            text = "Edit Mode",
            width = BUTTON_WIDTH,
            height = BUTTON_HEIGHT,
            template = "SecureActionButtonTemplate, SecureHandlerClickTemplate",
            secureAction = {},
            onClick = function()
                pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION)
                if frame then frame:Hide() end
            end,
        })
        if InCombatLockdown() then
            editModeBtn:RegisterEvent("PLAYER_REGEN_ENABLED")
            editModeBtn:HookScript("OnEvent", function(self, event)
                if event == "PLAYER_REGEN_ENABLED" then
                    SecureHandlerSetFrameRef(self, "em", EditModeManagerFrame)
                    self:SetAttribute("_onclick", [[ self:GetFrameRef("em"):Show() ]])
                    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                end
            end)
        else
            SecureHandlerSetFrameRef(editModeBtn, "em", EditModeManagerFrame)
            editModeBtn:SetAttribute("_onclick", [[ self:GetFrameRef("em"):Show() ]])
        end
        AddButton(editModeBtn)
    end

    -- 8. Cooldown Manager
    AddButton(Controls:CreateButton({
        parent = frame,
        text = "Cooldown Manager",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = MakeButtonAction(function()
            if addon.OpenCooldownManagerSettings then
                addon:OpenCooldownManagerSettings()
            end
        end),
    }))

    -- 9. Support
    AddButton(Controls:CreateButton({
        parent = frame,
        text = "Support",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = MakeButtonAction(function()
            ToggleHelpFrame()
        end),
    }))

    -- 10. Macros (conditional)
    if not (C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule
            and Enum.GameRule.MacrosDisabled and C_GameRules.IsGameRuleActive(Enum.GameRule.MacrosDisabled)) then
        AddButton(Controls:CreateButton({
            parent = frame,
            text = "Macros",
            width = BUTTON_WIDTH,
            height = BUTTON_HEIGHT,
            onClick = MakeButtonAction(function()
                ShowMacroFrame()
            end),
        }))
    end

    AddSectionBreak()

    -- 11. Log Out - uses SecureActionButtonTemplate /logout macro to avoid ADDON_ACTION_FORBIDDEN
    AddButton(Controls:CreateButton({
        parent = frame,
        text = "Log Out",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        secureAction = { type = "macro", macrotext = "/logout" },
        onClick = function()
            pcall(PlaySound, SOUNDKIT.IG_MAINMENU_LOGOUT)
            if frame then frame:Hide() end
        end,
    }))

    -- 12. Exit Game - uses SecureActionButtonTemplate /quit macro to avoid ADDON_ACTION_FORBIDDEN
    AddButton(Controls:CreateButton({
        parent = frame,
        text = "Exit Game",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        secureAction = { type = "macro", macrotext = "/quit" },
        onClick = function()
            pcall(PlaySound, SOUNDKIT.IG_MAINMENU_QUIT)
            if frame then frame:Hide() end
        end,
    }))

    AddSectionBreak()

    -- 13. Return to Game
    AddButton(Controls:CreateButton({
        parent = frame,
        text = "Return to Game",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            pcall(PlaySound, SOUNDKIT.IG_MAINMENU_CLOSE)
            if frame then frame:Hide() end
        end,
    }))

    -- Compute final height
    local totalHeight = math.abs(yOffset) + PADDING_BOTTOM
    frame:SetHeight(totalHeight)
end

--------------------------------------------------------------------------------
-- Frame Initialization (lazy, on first Show)
--------------------------------------------------------------------------------

local function InitializeFrame()
    if initialized then return end
    initialized = true

    frame = Window:Create("ScootGameMenuFrame", UIParent, MENU_WIDTH, 1)
    frame:SetMovable(false)
    frame:EnableMouse(true)
    frame:Hide()

    -- Center on screen
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    -- Register for ESC-to-close
    tinsert(UISpecialFrames, "ScootGameMenuFrame")

    -- Header: "Game Menu" title
    local title = frame:CreateFontString(nil, "OVERLAY")
    Theme:ApplyHeaderFont(title, 14)
    title:SetPoint("TOP", frame, "TOP", 0, -14)
    title:SetText("Game Menu")
    frame._title = title

    -- Info icon to the right of title
    Controls:CreateInfoIconForLabel({
        label = title,
        tooltipTitle = "Scoot Game Menu",
        tooltipText = "To switch back to the default menu, go to Scoot > Interface > Misc.",
        size = 14,
        position = "right",
        offsetX = 8,
    })

    -- When custom menu is closed out of combat, restore GameMenuFrame if alpha-hidden
    frame:HookScript("OnHide", function()
        if blizzMenuAlphaHidden and not InCombatLockdown() then
            RestoreBlizzardGameMenu()
            if GameMenuFrame:IsShown() then
                pcall(HideUIPanel, GameMenuFrame)
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function GameMenu:Show()
    InitializeFrame()

    -- Re-entrancy guard: if already shown, toggle off
    if frame:IsShown() then
        frame:Hide()
        return
    end

    -- Skip rebuild during combat if buttons already exist (button set is stable mid-combat)
    if not InCombatLockdown() or #buttons == 0 then
        BuildButtons()
    end

    -- Re-center (in case resolution changed); skip during combat (frame is protected)
    if not InCombatLockdown() then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    frame:Show()
end

function GameMenu:Hide()
    if frame then
        frame:Hide()
    end
end

function GameMenu:IsShown()
    return frame and frame:IsShown()
end

--------------------------------------------------------------------------------
-- Hook Installation (called once on PLAYER_ENTERING_WORLD)
--------------------------------------------------------------------------------

function GameMenu:InstallHook()
    if hookInstalled then return end
    hookInstalled = true

    if not GameMenuFrame then return end

    GameMenuFrame:HookScript("OnShow", function(self)
        if not IsSettingEnabled() then return end

        if blizzMenuAlphaHidden then
            -- Re-shown while already alpha-hidden (e.g., sub-panel closed), re-suppress
            GameMenuFrame:SetAlpha(0)
            GameMenuFrame:EnableMouse(false)
            return
        end

        if InCombatLockdown() then
            -- HideUIPanel is blocked during combat; visually hide instead
            GameMenuFrame:SetAlpha(0)
            GameMenuFrame:EnableMouse(false)
            blizzMenuAlphaHidden = true
            -- Defer Show() to next frame to escape the secure FramePositionDelegate
            -- handler chain. Show() on any frame is blocked from addon code running
            -- within a secure handler during combat lockdown.
            C_Timer.After(0, function()
                if blizzMenuAlphaHidden then
                    GameMenu:Show()
                end
            end)
        else
            HideUIPanel(GameMenuFrame)
            GameMenu:Show()
        end
    end)

    -- When GameMenuFrame hides during alpha-hidden state (ESC in combat),
    -- also close the custom menu for single-ESC-press behavior
    GameMenuFrame:HookScript("OnHide", function()
        if blizzMenuAlphaHidden then
            RestoreBlizzardGameMenu()
            if frame and frame:IsShown() then
                frame:Hide()
            end
        end
    end)
end

-- Register hook installation on PLAYER_ENTERING_WORLD + combat-end cleanup
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hookFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
hookFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        GameMenu:InstallHook()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_REGEN_ENABLED" then
        if blizzMenuAlphaHidden then
            RestoreBlizzardGameMenu()
            if GameMenuFrame:IsShown() then
                pcall(HideUIPanel, GameMenuFrame)
            end
        end
    end
end)
