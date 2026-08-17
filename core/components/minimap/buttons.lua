--------------------------------------------------------------------------------
-- buttons.lua - Minimap addon button container, menu, and button border styling
--
-- Addon button container/menu, button border styling, tracking button,
-- mail button with event handler.
--------------------------------------------------------------------------------

local addonName, addon = ...

local MM = addon.Minimap

-- Import shared helpers as locals
local getMinimapDB = MM._getMinimapDB

-- Addon button container state
local buttonContainerFrame = nil
local buttonContainerMenu = nil
local buttonContainerCloseListener = nil
local managedButtons = {}  -- Buttons currently hidden/managed by container
local originalButtonStates = {}  -- Store original visibility states
local buttonShowHooks = {}  -- Track which buttons have Show hooks installed

-- Tracking button state
local trackingButtonFrame = nil

-- Mail button state
local mailButtonFrame = nil
local mailEventFrame = nil

--------------------------------------------------------------------------------
-- Addon Button Container
--------------------------------------------------------------------------------

-- Blizzard-owned children of Minimap that must never be aggregated.
local BLIZZ_MINIMAP_CHILDREN = {
    MinimapZoomIn = true, MinimapZoomOut = true, MinimapBackdrop = true,
    MinimapCompassTexture = true, MinimapNorthTag = true, MinimapPing = true,
    MinimapZoneTextButton = true, MiniMapMailFrame = true, MiniMapMailIcon = true,
    MiniMapTracking = true, MiniMapTrackingFrame = true, MinimapTrackingButton = true,
    GameTimeFrame = true, QueueStatusButton = true, QueueStatusFrame = true,
    TimeManagerClockButton = true, GarrisonLandingPageMinimapButton = true,
    ExpansionLandingPageMinimapButton = true, MiniMapInstanceDifficulty = true,
    GuildInstanceDifficulty = true, MiniMapVoiceChatFrame = true,
    MiniMapWorldMapButton = true,
}

-- Collect all minimap addon buttons.
-- Two passes: LibDBIcon registry, then Minimap children (for addons that roll
-- their own button without using LibDBIcon, e.g. AutomaticRoleCheck). The
-- `seen` set de-duplicates by frame identity, which was the original duplicate
-- bug — LibDBIcon parents its buttons to Minimap, so a naive children scan saw
-- the same frame twice.
local function CollectMinimapAddonButtons()
    local buttons, seen = {}, {}

    local LibDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LibDBIcon and LibDBIcon.objects then
        for name, button in pairs(LibDBIcon.objects) do
            if button and button:IsObjectType("Button") then
                buttons[name] = { button = button, name = name }
                seen[button] = true
            end
        end
    end

    if Minimap and Minimap.GetChildren then
        for _, child in ipairs({ Minimap:GetChildren() }) do
            if child and child.IsObjectType and child:IsObjectType("Button") and not seen[child] then
                local name = child.GetName and child:GetName()
                local w, h = child:GetWidth() or 0, child:GetHeight() or 0
                -- Skip world-map pin frames (HandyNotes, HereBeDragons, etc.): typically
                -- <16px and named like FooPin1, FooPin2. Real addon buttons are 24-32px.
                if name
                    and w >= 20 and h >= 20
                    and not BLIZZ_MINIMAP_CHILDREN[name]
                    and not name:find("^Scoot")
                    and not name:find("Pin%d+$")
                then
                    buttons[name] = { button = child, name = name }
                    seen[child] = true
                end
            end
        end
    end

    return buttons
end

-- Find the border texture on an addon button (typically 50x50 OVERLAY texture)
local function FindButtonBorderTexture(button)
    if not button then return nil end

    local regions = { button:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") and region:GetDrawLayer() == "OVERLAY" then
            local w, h = region:GetSize()
            if w and h and math.abs(w - 50) < 5 and math.abs(h - 50) < 5 then
                return region
            end
        end
    end

    -- Also check for border in children (some buttons nest the border)
    local children = { button:GetChildren() }
    for _, child in ipairs(children) do
        local childRegions = { child:GetRegions() }
        for _, region in ipairs(childRegions) do
            if region:IsObjectType("Texture") and region:GetDrawLayer() == "OVERLAY" then
                local w, h = region:GetSize()
                if w and h and math.abs(w - 50) < 5 and math.abs(h - 50) < 5 then
                    return region
                end
            end
        end
    end
end

-- Texture paths used as the dark/blank minimap-button backdrop disc — must be
-- rejected when sniffing for the real icon.
local BACKDROP_TEXTURE_PATTERNS = {
    "UI%-Minimap%-Background",
    "MiniMap%-TrackingBorder",
    "MiniMap%-TrackingBackground",
}

local function isBackdropTexture(path)
    if type(path) ~= "string" then return false end
    for _, pat in ipairs(BACKDROP_TEXTURE_PATTERNS) do
        if path:find(pat) then return true end
    end
    return false
end

-- Get the icon texture from an addon button. Prefers ARTWORK > BORDER > BACKGROUND
-- so the result is the addon icon and not the dark minimap backdrop disc that
-- some addons (e.g. AutomaticRoleCheck) layer underneath their icon.
local function GetButtonIconTexture(button)
    if not button then return nil end

    -- Check for icon child frame first (LibDBIcon pattern)
    if button.icon and button.icon:IsObjectType("Texture") then
        local tex = button.icon:GetTexture()
        if tex and not isBackdropTexture(tex) then return tex end
    end

    local layerPriority = { ARTWORK = 1, BORDER = 2, BACKGROUND = 3 }
    local best, bestRank
    for _, region in ipairs({ button:GetRegions() }) do
        if region:IsObjectType("Texture") then
            local layer = region:GetDrawLayer()
            local w, h = region:GetSize()
            if w and h and w < 45 and h < 45 and layer ~= "OVERLAY" then
                local tex = region:GetTexture()
                if tex and not isBackdropTexture(tex) then
                    local rank = layerPriority[layer] or 99
                    if not bestRank or rank < bestRank then
                        best, bestRank = tex, rank
                    end
                end
            end
        end
    end
    return best
end

-- Create the container button (shown on minimap)
local function CreateButtonContainer()
    if buttonContainerFrame then
        return buttonContainerFrame
    end

    local container = CreateFrame("Button", "ScootMinimapButtonContainer", UIParent)
    container:SetSize(24, 24)  -- Hitbox matches icon size
    container:SetFrameStrata("MEDIUM")
    container:SetFrameLevel(8)

    -- Arrow icon only (no background, no border ring)
    local icon = container:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas("friendslist-categorybutton-arrow-down")
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER", container, "CENTER", 0, 0)
    icon:SetDesaturated(true)
    icon:SetVertexColor(1, 1, 1, 1)
    container.icon = icon

    -- Click handler
    container:SetScript("OnClick", function(self, button)
        if buttonContainerMenu and buttonContainerMenu:IsShown() then
            buttonContainerMenu:Hide()
        else
            if buttonContainerMenu then
                buttonContainerMenu:Show()
            end
        end
    end)

    -- Tooltip
    container:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Minimap Addons")
        GameTooltip:AddLine("Click to show addon buttons", 1, 1, 1)
        GameTooltip:Show()
    end)

    container:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    buttonContainerFrame = container
    MM._buttonContainerFrame = container
    addon.RegisterPetBattleFrame(container)
    return container
end

-- Create a menu entry button for a managed addon button
local function CreateMenuEntry(parent, buttonInfo, index)
    local entry = CreateFrame("Button", nil, parent)
    entry:SetSize(32, 32)

    -- Icon from original button
    local iconTex = GetButtonIconTexture(buttonInfo.button)
    local icon = entry:CreateTexture(nil, "ARTWORK")
    if iconTex then
        if type(iconTex) == "number" then
            icon:SetTexture(iconTex)
        else
            icon:SetTexture(iconTex)
        end
    else
        icon:SetTexture(134400)  -- Fallback: Question mark icon
    end
    icon:SetSize(24, 24)
    icon:SetPoint("CENTER", entry, "CENTER", 0, 0)
    entry.icon = icon

    -- Highlight
    local highlight = entry:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(136467)
    highlight:SetSize(32, 32)
    highlight:SetPoint("CENTER")
    highlight:SetVertexColor(0.3, 0.3, 0.3, 0.5)

    -- Click handler - simulate click on original button
    entry:SetScript("OnClick", function(self, mouseButton)
        local origButton = buttonInfo.button
        if origButton then
            -- Temporarily show the button to allow click
            local wasHidden = not origButton:IsShown()
            if wasHidden then
                origButton:Show()
            end

            -- Simulate click
            if origButton:GetScript("OnClick") then
                origButton:GetScript("OnClick")(origButton, mouseButton)
            end

            -- Re-hide if it was temporarily shown
            if wasHidden then
                origButton:Hide()
            end

            -- Hide menu after click
            if buttonContainerMenu then
                buttonContainerMenu:Hide()
            end
        end
    end)

    -- Tooltip from original button
    entry:SetScript("OnEnter", function(self)
        local origButton = buttonInfo.button
        if origButton then
            -- Copy tooltip behavior from original
            if origButton:GetScript("OnEnter") then
                -- Position tooltip at this entry
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                -- Try to get tooltip from original
                local origOnEnter = origButton:GetScript("OnEnter")
                pcall(origOnEnter, origButton)
            else
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(buttonInfo.name or "Addon Button")
                GameTooltip:Show()
            end
        end
    end)

    entry:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    return entry
end

-- Create the dropdown menu
local function CreateButtonContainerMenu()
    if buttonContainerMenu then
        return buttonContainerMenu
    end

    local menu = CreateFrame("Frame", "ScootMinimapMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:SetFrameLevel(100)
    menu:SetClampedToScreen(true)

    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    menu:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    menu.entries = {}

    -- Close on escape
    addon.EscapeKey.Attach(menu, function(self)
        self:Hide()
    end)

    menu:Hide()

    buttonContainerMenu = menu
    addon.RegisterPetBattleFrame(menu)

    -- Create close listener (fullscreen invisible button)
    if not buttonContainerCloseListener then
        local listener = CreateFrame("Button", nil, UIParent)
        listener:SetFrameStrata("DIALOG")
        listener:SetFrameLevel(99)
        listener:SetAllPoints(UIParent)
        listener:Hide()

        listener:SetScript("OnClick", function()
            if buttonContainerMenu then
                buttonContainerMenu:Hide()
            end
        end)

        buttonContainerCloseListener = listener
    end

    -- Show/hide close listener with menu
    menu:SetScript("OnShow", function(self)
        if buttonContainerCloseListener then
            buttonContainerCloseListener:Show()
        end
    end)

    menu:SetScript("OnHide", function(self)
        if buttonContainerCloseListener then
            buttonContainerCloseListener:Hide()
        end
    end)

    return menu
end

-- Update the menu with current managed buttons
local function UpdateButtonContainerMenu()
    if not buttonContainerMenu then
        CreateButtonContainerMenu()
    end

    local menu = buttonContainerMenu

    -- Clear existing entries
    for _, entry in ipairs(menu.entries) do
        entry:Hide()
        entry:SetParent(nil)
    end
    wipe(menu.entries)

    -- Get sorted list of managed buttons
    local sortedButtons = {}
    for name, info in pairs(managedButtons) do
        table.insert(sortedButtons, { name = name, info = info })
    end
    table.sort(sortedButtons, function(a, b) return a.name < b.name end)

    -- Single vertical column layout
    local numButtons = #sortedButtons
    local cols = 1  -- Always single column
    local rows = numButtons

    local padding = 4
    local buttonSize = 32
    local menuWidth = buttonSize + (padding * 2)
    local menuHeight = (rows * buttonSize) + ((rows + 1) * padding)

    menu:SetSize(menuWidth, menuHeight)

    -- Position centered directly beneath container button
    if buttonContainerFrame then
        menu:ClearAllPoints()
        menu:SetPoint("TOP", buttonContainerFrame, "BOTTOM", 0, -5)
    end

    -- Create entry buttons (single column)
    for i, buttonData in ipairs(sortedButtons) do
        local entry = CreateMenuEntry(menu, buttonData.info, i)

        entry:ClearAllPoints()
        entry:SetPoint("TOPLEFT", menu, "TOPLEFT", padding, -(padding + ((i - 1) * (buttonSize + padding))))

        table.insert(menu.entries, entry)
    end
end

-- Apply addon button container settings
local function ApplyButtonContainerStyle(db)
    if not db then
        -- No config, ensure container is hidden
        if buttonContainerFrame then
            buttonContainerFrame:Hide()
        end
        if buttonContainerMenu then
            buttonContainerMenu:Hide()
        end
        -- Restore any hidden buttons
        for name, info in pairs(managedButtons) do
            if info.button and originalButtonStates[name] ~= false then
                info.button:Show()
            end
        end
        wipe(managedButtons)
        wipe(originalButtonStates)
        return
    end

    local enabled = db.addonButtonContainerEnabled

    if not enabled then
        -- Disable container - restore hidden buttons
        if buttonContainerFrame then
            buttonContainerFrame:Hide()
        end
        if buttonContainerMenu then
            buttonContainerMenu:Hide()
        end

        -- Restore managed buttons
        for name, info in pairs(managedButtons) do
            if info.button and originalButtonStates[name] ~= false then
                info.button:Show()
            end
        end
        wipe(managedButtons)
        wipe(originalButtonStates)
        return
    end

    -- Container enabled
    local container = CreateButtonContainer()
    CreateButtonContainerMenu()

    -- Position container
    local minimap = _G.Minimap
    if minimap then
        local anchor = db.addonButtonContainerAnchor or "BOTTOMRIGHT"
        local offsetX = tonumber(db.addonButtonContainerOffsetX) or 0
        local offsetY = tonumber(db.addonButtonContainerOffsetY) or 0

        container:ClearAllPoints()
        container:SetPoint(anchor, minimap, anchor, offsetX, offsetY)
    end

    -- Collect and manage buttons
    local allButtons = CollectMinimapAddonButtons()
    local keepScootSeparate = db.scootButtonSeparate
    local keepBugSackSeparate = addon.db and addon.db.profile and addon.db.profile.bugSackButtonSeparate

    wipe(managedButtons)

    for name, info in pairs(allButtons) do
        -- Check if this is Scoot's or BugSack's button
        local isScoot = name:lower():match("scoot") or name == "LibDBIcon10_Scoot"
        local isBugSack = name:lower():match("bugsack") or name == "LibDBIcon10_BugSack"

        if (isScoot and keepScootSeparate) or (isBugSack and keepBugSackSeparate) then
            -- Keep this button visible
            if info.button then
                info.button:Show()
            end
        else
            -- Hide and manage this button
            if info.button then
                -- Store original state before hiding
                if originalButtonStates[name] == nil then
                    originalButtonStates[name] = info.button:IsShown()
                end

                -- Install hook to re-hide when LibDBIcon tries to show it
                if not buttonShowHooks[name] then
                    buttonShowHooks[name] = true
                    hooksecurefunc(info.button, "Show", function(self)
                        local db = getMinimapDB()
                        if db and db.addonButtonContainerEnabled then
                            -- Check if this button should still be hidden
                            local keepScootSeparate = db.scootButtonSeparate
                            local keepBugSackSeparate = addon.db and addon.db.profile and addon.db.profile.bugSackButtonSeparate
                            local isScoot = name:lower():match("scoot") or name == "LibDBIcon10_Scoot"
                            local isBugSack = name:lower():match("bugsack") or name == "LibDBIcon10_BugSack"
                            if not ((isScoot and keepScootSeparate) or (isBugSack and keepBugSackSeparate)) then
                                self:Hide()
                            end
                        end
                    end)
                end

                info.button:Hide()
                managedButtons[name] = info
            end
        end
    end

    -- Update menu content
    UpdateButtonContainerMenu()

    -- Show container if there are managed buttons
    if next(managedButtons) then
        container:Show()
    else
        container:Hide()
    end
end

-- Apply addon button border styling (hide or tint)
local function ApplyAddonButtonBorderStyle(db)
    local allButtons = CollectMinimapAddonButtons()

    for name, info in pairs(allButtons) do
        local button = info.button
        if not button then return end

        -- Find border (OVERLAY ~50x50) and background (BACKGROUND ~24x24)
        local border, background
        local regions = { button:GetRegions() }
        for _, region in ipairs(regions) do
            if region:IsObjectType("Texture") then
                local layer = region:GetDrawLayer()
                local w, h = region:GetSize()
                if layer == "OVERLAY" and w and h and math.abs(w - 50) < 5 then
                    border = region
                elseif layer == "BACKGROUND" and w and h and math.abs(w - 24) < 5 then
                    background = region
                end
            end
        end

        if db and db.hideAddonButtonBorders then
            -- Hide border ring
            if border then border:SetAlpha(0) end
            -- Hide background circle mask
            if background then background:SetAlpha(0) end
            -- Clear hover highlight (get texture directly for reliability)
            local highlight = button:GetHighlightTexture()
            if highlight then
                highlight:SetAlpha(0)
            end
        elseif db and db.addonButtonBorderTintEnabled and db.addonButtonBorderTintColor then
            -- Tint mode (restore visibility, apply tint)
            if border then
                border:SetAlpha(1)
                border:SetDesaturated(true)
                local c = db.addonButtonBorderTintColor
                border:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            end
            if background then background:SetAlpha(1) end
            -- Restore highlight
            local highlight = button:GetHighlightTexture()
            if highlight then
                highlight:SetAlpha(1)
            end
        else
            -- Restore defaults
            if border then
                border:SetAlpha(1)
                border:SetDesaturated(false)
                border:SetVertexColor(1, 1, 1, 1)
            end
            if background then background:SetAlpha(1) end
            local highlight = button:GetHighlightTexture()
            if highlight then
                highlight:SetAlpha(1)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Custom Tracking Button
--------------------------------------------------------------------------------

local function CreateTrackingButton()
    if trackingButtonFrame then
        return trackingButtonFrame
    end

    local btn = CreateFrame("Button", "ScootTrackingButton", UIParent)
    btn:SetSize(24, 24)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)

    -- Magnifying glass icon (Blizzard tracking atlas), desaturated white
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas("ui-hud-minimap-tracking-up")
    icon:SetSize(24, 24)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetDesaturated(true)
    icon:SetVertexColor(1, 1, 1, 1)
    btn.icon = icon

    -- Click handler: open Blizzard's tracking dropdown
    btn:SetScript("OnClick", function(self, mouseButton)
        local trackingBtn = MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button
        if not trackingBtn then return end

        -- Toggle: close if already open
        if trackingBtn:IsMenuOpen() then
            trackingBtn:CloseMenu()
            return
        end

        -- Generate/refresh the menu description (uses generator from MiniMapTrackingButtonMixin:OnLoad)
        trackingBtn:GenerateMenu()
        if not trackingBtn.menuDescription then return end

        -- Open with the Scoot button as owner so the menu stays visible.
        -- Blizzard's Menu.lua auto-closes menus when owner:IsVisible() is false.
        -- The Blizzard tracking button is hidden when dock is hidden, so passing it
        -- as owner causes immediate closure. The Scoot button is always visible.
        local anchor = AnchorUtil.CreateAnchor("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        local menu = Menu.GetManager():OpenMenu(self, trackingBtn.menuDescription, anchor)

        if menu then
            trackingBtn.menu = menu
            menu:SetClosedCallback(function()
                trackingBtn.menu = nil
            end)
        end
    end)

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Tracking")
        GameTooltip:AddLine("Click to set tracking options", 1, 1, 1)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    trackingButtonFrame = btn
    MM._trackingButtonFrame = btn
    addon.RegisterPetBattleFrame(btn)
    return btn
end

local function ApplyTrackingButtonStyle(db)
    if not db or not db.trackingButtonEnabled then
        if trackingButtonFrame then
            trackingButtonFrame:Hide()
        end
        return
    end

    local btn = CreateTrackingButton()
    local minimap = _G.Minimap
    if not minimap then return end

    local anchor = db.trackingButtonAnchor or "TOPLEFT"
    local offsetX = tonumber(db.trackingButtonOffsetX) or 0
    local offsetY = tonumber(db.trackingButtonOffsetY) or 0

    btn:ClearAllPoints()
    btn:SetPoint(anchor, minimap, anchor, offsetX, offsetY)
    btn:Show()
end

--------------------------------------------------------------------------------
-- Custom Mail Notification Button
--------------------------------------------------------------------------------

local function CreateMailButton()
    if mailButtonFrame then
        return mailButtonFrame
    end

    local btn = CreateFrame("Button", "ScootMailButton", UIParent)
    btn:SetSize(24, 24)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)

    -- Mail icon (Blizzard mail atlas), desaturated white
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas("ui-hud-minimap-mail-up")
    icon:SetSize(24, 24)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetDesaturated(true)
    icon:SetVertexColor(1, 1, 1, 1)
    btn.icon = icon

    -- Tooltip (replicates Blizzard's MinimapMailFrameUpdate pattern)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local senders = { GetLatestThreeSenders() }
        local headerText = #senders >= 1 and HAVE_MAIL_FROM or HAVE_MAIL
        FormatUnreadMailTooltip(GameTooltip, headerText, senders)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    mailButtonFrame = btn
    MM._mailButtonFrame = btn
    addon.RegisterPetBattleFrame(btn)
    return btn
end

local function ApplyMailButtonStyle(db)
    if not db or not db.mailButtonEnabled then
        if mailButtonFrame then
            mailButtonFrame:Hide()
        end
        return
    end

    -- Check if player has mail (pcall for secret safety)
    local ok, hasMail = pcall(HasNewMail)
    if not ok or not hasMail then
        if mailButtonFrame then
            mailButtonFrame:Hide()
        end
        return
    end

    local btn = CreateMailButton()
    local minimap = _G.Minimap
    if not minimap then return end

    local anchor = db.mailButtonAnchor or "TOPRIGHT"
    local offsetX = tonumber(db.mailButtonOffsetX) or 0
    local offsetY = tonumber(db.mailButtonOffsetY) or 0

    btn:ClearAllPoints()
    btn:SetPoint(anchor, minimap, anchor, offsetX, offsetY)
    btn:Show()
end

local function EnsureMailEventHandler()
    if mailEventFrame then return end

    mailEventFrame = CreateFrame("Frame")
    mailEventFrame:RegisterEvent("UPDATE_PENDING_MAIL")
    mailEventFrame:SetScript("OnEvent", function(self, event)
        local db = getMinimapDB()
        if db then
            ApplyMailButtonStyle(db)
        end
    end)
end

-- Promote to namespace for core orchestrator
MM._ApplyButtonContainerStyle = ApplyButtonContainerStyle
MM._ApplyAddonButtonBorderStyle = ApplyAddonButtonBorderStyle
MM._ApplyTrackingButtonStyle = ApplyTrackingButtonStyle
MM._ApplyMailButtonStyle = ApplyMailButtonStyle
MM._EnsureMailEventHandler = EnsureMailEventHandler
